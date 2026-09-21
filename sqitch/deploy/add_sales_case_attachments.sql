-- Deploy floq:add_sales_case_attachments to pg
-- requires: add_sales_pipeline

BEGIN;

-- Most cases arrive as a PDF somebody was sent. The bytes live in Cloudinary,
-- under an authenticated type that needs a signed URL to read; this table is the
-- index, and the only place that says which case a file belongs to.
CREATE TABLE sales_case_attachment (
    id            TEXT        CONSTRAINT sales_case_attachment_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id       TEXT        NOT NULL REFERENCES sales_case (id) ON DELETE CASCADE,
    filename      TEXT        NOT NULL,
    content_type  TEXT,
    byte_size     BIGINT      CONSTRAINT sales_case_attachment_has_bytes CHECK (byte_size IS NULL OR byte_size > 0),

    -- Cloudinary's own identifiers, together enough to sign a delivery URL.
    public_id     TEXT        NOT NULL CONSTRAINT sales_case_attachment_public_id_key UNIQUE,
    resource_type TEXT        NOT NULL DEFAULT 'raw',
    format        TEXT,

    uploaded_by   INTEGER     REFERENCES employees (id),
    uploaded_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX sales_case_attachment_case_idx ON sales_case_attachment (case_id, uploaded_at DESC);

INSERT INTO sales_event_kind (slug, label) VALUES
    ('attachment_added',   'La ved fil'),
    ('attachment_removed', 'Fjernet fil');

CREATE FUNCTION set_sales_attachment_uploader()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.uploaded_by = logged_in_employee_id();
    RETURN NEW;
END;
$$;

CREATE TRIGGER sales_case_attachment_uploader
    BEFORE INSERT ON sales_case_attachment
    FOR EACH ROW
    EXECUTE FUNCTION set_sales_attachment_uploader();

-- A file arriving or leaving is a change to the case, so it lands in the same log
-- as every other change rather than in a second place nobody thinks to read.
CREATE FUNCTION log_sales_attachment_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO sales_case_event (case_id, kind_slug, body, author_id)
        VALUES (NEW.case_id, 'attachment_added', NEW.filename, NEW.uploaded_by);
        RETURN NULL;
    END IF;

    -- Deleting a whole case cascades here after its own row has gone, so pointing
    -- at it would fail the foreign key. The event is still written, orphaned the
    -- same way the `deleted` event is, because an audit may not go quiet about a
    -- file disappearing.
    INSERT INTO sales_case_event (case_id, kind_slug, body, author_id)
    VALUES (
        (SELECT id FROM sales_case WHERE id = OLD.case_id),
        'attachment_removed',
        OLD.filename,
        logged_in_employee_id());

    RETURN NULL;
END;
$$;

CREATE TRIGGER sales_case_attachment_added
    AFTER INSERT ON sales_case_attachment
    FOR EACH ROW
    EXECUTE FUNCTION log_sales_attachment_change();

CREATE TRIGGER sales_case_attachment_removed
    AFTER DELETE ON sales_case_attachment
    FOR EACH ROW
    EXECUTE FUNCTION log_sales_attachment_change();

GRANT SELECT, INSERT, DELETE ON TABLE sales_case_attachment TO employee;
GRANT SELECT ON TABLE sales_case_attachment TO read_only;

ALTER TABLE sales_case_attachment ENABLE ROW LEVEL SECURITY;

CREATE POLICY sales_case_attachment_select_policy ON sales_case_attachment
    FOR SELECT USING (true);

CREATE POLICY sales_case_attachment_insert_policy ON sales_case_attachment
    FOR INSERT TO employee WITH CHECK (true);

-- Whoever put the file there may take it back, and an admin may take back
-- anybody's. Stricter than the card itself, which any employee may edit: a file
-- is somebody's document rather than a field on a shared card.
CREATE POLICY sales_case_attachment_delete_policy ON sales_case_attachment
    FOR DELETE TO employee
    USING (uploaded_by = logged_in_employee_id() OR check_admin_write_access());

COMMIT;
