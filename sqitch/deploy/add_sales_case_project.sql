BEGIN;

CREATE TABLE sales_case_project (
    case_id    TEXT        NOT NULL REFERENCES sales_case (id) ON DELETE CASCADE,
    project_id TEXT        NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
    created_by INTEGER     REFERENCES employees (id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT sales_case_project_pkey PRIMARY KEY (case_id, project_id)
);

CREATE INDEX sales_case_project_project_idx ON sales_case_project (project_id);

INSERT INTO sales_event_kind (slug, label) VALUES
    ('project_added',   'La til timekode'),
    ('project_removed', 'Fjernet timekode');

CREATE FUNCTION set_sales_case_project_author()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.created_by = logged_in_employee_id();
    RETURN NEW;
END;
$$;

CREATE TRIGGER sales_case_project_author
    BEFORE INSERT ON sales_case_project
    FOR EACH ROW
    EXECUTE FUNCTION set_sales_case_project_author();

CREATE FUNCTION log_sales_case_project_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    link         sales_case_project;
    kind         TEXT;
    project_name TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        link = NEW;
        kind = 'project_added';
    ELSE
        link = OLD;
        kind = 'project_removed';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM sales_case c WHERE c.id = link.case_id) THEN
        RETURN NULL;
    END IF;

    SELECT coalesce(nullif(btrim(p.internal_name), ''), p.name)
    INTO project_name
    FROM projects p
    WHERE p.id = link.project_id;

    INSERT INTO sales_case_event (case_id, kind_slug, payload)
    VALUES (link.case_id, kind, jsonb_build_object('projectId', link.project_id, 'name', project_name));

    RETURN NULL;
END;
$$;

CREATE TRIGGER sales_case_project_added
    AFTER INSERT ON sales_case_project
    FOR EACH ROW
    EXECUTE FUNCTION log_sales_case_project_change();

CREATE TRIGGER sales_case_project_removed
    AFTER DELETE ON sales_case_project
    FOR EACH ROW
    EXECUTE FUNCTION log_sales_case_project_change();

GRANT SELECT, INSERT, DELETE ON TABLE sales_case_project TO employee;
GRANT SELECT ON TABLE sales_case_project TO read_only;

ALTER TABLE sales_case_project ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_case_project_select_policy ON sales_case_project FOR SELECT USING (true);
CREATE POLICY sales_case_project_insert_policy ON sales_case_project FOR INSERT TO employee WITH CHECK (true);
CREATE POLICY sales_case_project_delete_policy ON sales_case_project FOR DELETE TO employee USING (true);

COMMIT;
