-- Deploy floq:add_sales_pipeline to pg
-- requires: employees_table
-- requires: time_tracking_tables
-- requires: add_employee_user
-- requires: add_read_only_user
-- requires: change_jwt_claim_retrieval

BEGIN;

-- The stages are data, not schema. Adding, renaming, reordering or changing the
-- hide rule is an INSERT/UPDATE, with no sqitch change and no platform deploy.
CREATE TABLE sales_stage (
    slug               TEXT    CONSTRAINT sales_stage_pkey PRIMARY KEY,
    label              TEXT    NOT NULL,
    sort_order         INTEGER NOT NULL,
    is_terminal        BOOLEAN NOT NULL DEFAULT FALSE,
    hides_after_months INTEGER,
    active             BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO sales_stage (slug, label, sort_order, is_terminal, hides_after_months) VALUES
    ('tips',                           'Tips',                           10, FALSE, NULL),
    ('identifisert',                   'Identifisert',                   20, FALSE, NULL),
    ('tilbud_paagaar',                 'Tilbud pågår',                   30, FALSE, NULL),
    ('tilbud_paagaar_underleverandor', 'Tilbud pågår – underleverandør', 40, FALSE, NULL),
    ('vunnet',                         'Vunnet',                         50, TRUE,  6),
    ('trukket',                        'Trukket',                        60, TRUE,  6),
    ('tapt',                           'Tapt',                           70, TRUE,  6);

CREATE TABLE sales_event_kind (
    slug  TEXT CONSTRAINT sales_event_kind_pkey PRIMARY KEY,
    label TEXT NOT NULL
);

INSERT INTO sales_event_kind (slug, label) VALUES
    ('created',      'Opprettet'),
    ('imported',     'Importert fra Trello'),
    ('comment',      'Kommentar'),
    ('stage_change', 'Flyttet'),
    ('field_change', 'Endret felt'),
    ('deleted',      'Slettet');

CREATE TABLE sales_case (
    id                  TEXT        CONSTRAINT sales_case_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    stage_slug          TEXT        NOT NULL REFERENCES sales_stage (slug),
    -- What the hide rule measures from. Maintained by sales_case_stage_since.
    stage_since         TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- A tip may name a customer we have no row for yet.
    customer_id         TEXT        REFERENCES customers (id),
    customer_text       TEXT,

    role                TEXT,
    owner_id            INTEGER     REFERENCES employees (id),
    next_step           TEXT,
    deadline            DATE,
    start_week          DATE,
    end_week            DATE,
    headcount           INTEGER,
    framework_agreement BOOLEAN     NOT NULL DEFAULT FALSE,
    source_text         TEXT,

    trello_card_id      TEXT        CONSTRAINT sales_case_trello_card_id_key UNIQUE,
    trello_url          TEXT,
    attachment_count    INTEGER     NOT NULL DEFAULT 0,

    extra               JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_by          INTEGER     REFERENCES employees (id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Always satisfiable from a Trello title, and droppable with one ALTER if it
    -- turns out to be in the way.
    CONSTRAINT sales_case_names_someone CHECK (customer_id IS NOT NULL OR customer_text IS NOT NULL)
);

CREATE INDEX sales_case_board_idx ON sales_case (stage_slug, stage_since DESC);

CREATE TABLE sales_case_event (
    id          TEXT        CONSTRAINT sales_case_event_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Nullable, and SET NULL rather than CASCADE: a deleted case must not take the
    -- record of who deleted it with it. The board reads events by case_id, so an
    -- orphan is invisible there and still in the log.
    case_id     TEXT        REFERENCES sales_case (id) ON DELETE SET NULL,
    kind_slug   TEXT        NOT NULL REFERENCES sales_event_kind (slug),
    body        TEXT,
    from_stage  TEXT        REFERENCES sales_stage (slug),
    to_stage    TEXT        REFERENCES sales_stage (slug),
    author_id   INTEGER     REFERENCES employees (id),
    -- A Trello name with no employee to match it to.
    author_text TEXT,
    payload     JSONB       NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX sales_case_event_case_idx ON sales_case_event (case_id, occurred_at DESC);

-- nullif: a pooled connection that has been reset carries '' rather than no value
-- at all, and ''::json raises instead of returning nothing.
CREATE FUNCTION logged_in_employee_id()
    RETURNS INTEGER
    LANGUAGE sql
    STABLE
AS
$$
SELECT id
FROM employees
WHERE email = nullif(current_setting('request.jwt.claims', true), '')::json ->> 'email';
$$;

CREATE FUNCTION set_sales_case_author()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.created_by = logged_in_employee_id();
    RETURN NEW;
END;
$$;

CREATE TRIGGER sales_case_author
    BEFORE INSERT ON sales_case
    FOR EACH ROW
    EXECUTE FUNCTION set_sales_case_author();

CREATE FUNCTION set_sales_case_stage_since()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF NEW.stage_slug IS DISTINCT FROM OLD.stage_slug THEN
        NEW.stage_since = clock_timestamp();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER sales_case_stage_since
    BEFORE UPDATE ON sales_case
    FOR EACH ROW
    EXECUTE FUNCTION set_sales_case_stage_since();

-- Everything that happens to a case is written here, by the database rather than by
-- each writer remembering to: whoever holds the connection is named, whatever wrote
-- the row. That is the whole point of keeping the log down here — psql, a migration
-- and the API all land in the same place.

-- A card that came from Trello was not created here, so the import's own `imported`
-- event stands alone rather than claiming the importer made it up.
CREATE FUNCTION log_sales_case_created()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO sales_case_event (case_id, kind_slug, to_stage, author_id)
    VALUES (NEW.id, 'created', NEW.stage_slug, NEW.created_by);

    RETURN NULL;
END;
$$;

CREATE TRIGGER sales_case_created
    AFTER INSERT ON sales_case
    FOR EACH ROW
    WHEN (NEW.trello_card_id IS NULL)
    EXECUTE FUNCTION log_sales_case_created();

CREATE FUNCTION log_sales_case_stage_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO sales_case_event (case_id, kind_slug, from_stage, to_stage, author_id)
    VALUES (NEW.id, 'stage_change', OLD.stage_slug, NEW.stage_slug, logged_in_employee_id());

    RETURN NULL;
END;
$$;

CREATE TRIGGER sales_case_stage_change
    AFTER UPDATE OF stage_slug ON sales_case
    FOR EACH ROW
    WHEN (NEW.stage_slug IS DISTINCT FROM OLD.stage_slug)
    EXECUTE FUNCTION log_sales_case_stage_change();

-- Which fields changed, from what to what, as one event rather than one per field.
-- Diffed generically from the row itself, so a column added later is audited without
-- anyone remembering to list it here. The five excluded are the ones another trigger
-- or another event already accounts for.
CREATE FUNCTION log_sales_case_field_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    changes JSONB;
BEGIN
    SELECT jsonb_agg(jsonb_build_object('field', key, 'from', to_jsonb(OLD) -> key, 'to', value)
                     ORDER BY key)
    INTO changes
    FROM jsonb_each(to_jsonb(NEW))
    WHERE to_jsonb(OLD) -> key IS DISTINCT FROM value
      AND key NOT IN ('id', 'stage_slug', 'stage_since', 'created_at', 'created_by');

    IF changes IS NOT NULL THEN
        INSERT INTO sales_case_event (case_id, kind_slug, author_id, payload)
        VALUES (NEW.id, 'field_change', logged_in_employee_id(), jsonb_build_object('changes', changes));
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER sales_case_field_change
    AFTER UPDATE ON sales_case
    FOR EACH ROW
    EXECUTE FUNCTION log_sales_case_field_change();

-- BEFORE, so the row is still there to describe. The event outlives the case it
-- points at, which is why case_id is nullable.
CREATE FUNCTION log_sales_case_deleted()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO sales_case_event (case_id, kind_slug, from_stage, author_id, payload)
    VALUES (OLD.id, 'deleted', OLD.stage_slug, logged_in_employee_id(),
            jsonb_build_object('case', to_jsonb(OLD)));

    RETURN OLD;
END;
$$;

CREATE TRIGGER sales_case_deleted
    BEFORE DELETE ON sales_case
    FOR EACH ROW
    EXECUTE FUNCTION log_sales_case_deleted();

-- A row names one author: an employee, or a Trello name we could not match.
CREATE FUNCTION set_sales_case_event_author()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF NEW.author_text IS NULL THEN
        NEW.author_id = logged_in_employee_id();
    ELSE
        NEW.author_id = NULL;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER sales_case_event_author
    BEFORE INSERT ON sales_case_event
    FOR EACH ROW
    EXECUTE FUNCTION set_sales_case_event_author();

-- An admin changes the stages from the app, which is what keeps a product decision
-- out of sqitch. No DELETE: a stage rows point at is retired with `active`.
GRANT SELECT, INSERT, UPDATE ON TABLE sales_stage TO employee;
GRANT SELECT, INSERT, UPDATE ON TABLE sales_event_kind TO employee;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE sales_case TO employee;
GRANT SELECT, INSERT ON TABLE sales_case_event TO employee;

GRANT SELECT ON TABLE sales_stage TO read_only;
GRANT SELECT ON TABLE sales_event_kind TO read_only;
GRANT SELECT ON TABLE sales_case TO read_only;
GRANT SELECT ON TABLE sales_case_event TO read_only;

-- Written out rather than enable_default_row_level_security(), which grants every
-- employee the same write it grants a reader. The board is the whole company's to
-- read and to add to; only removal is an admin's.
ALTER TABLE sales_stage ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_stage_select_policy ON sales_stage FOR SELECT USING (true);
CREATE POLICY sales_stage_write_policy ON sales_stage FOR ALL TO employee
    USING (check_admin_write_access()) WITH CHECK (check_admin_write_access());

ALTER TABLE sales_event_kind ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_event_kind_select_policy ON sales_event_kind FOR SELECT USING (true);
CREATE POLICY sales_event_kind_write_policy ON sales_event_kind FOR ALL TO employee
    USING (check_admin_write_access()) WITH CHECK (check_admin_write_access());

ALTER TABLE sales_case ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_case_select_policy ON sales_case FOR SELECT USING (true);
CREATE POLICY sales_case_insert_policy ON sales_case FOR INSERT TO employee WITH CHECK (true);
CREATE POLICY sales_case_update_policy ON sales_case FOR UPDATE TO employee
    USING (true) WITH CHECK (true);
CREATE POLICY sales_case_delete_policy ON sales_case FOR DELETE TO employee
    USING (check_admin_write_access());

ALTER TABLE sales_case_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_case_event_select_policy ON sales_case_event FOR SELECT USING (true);
CREATE POLICY sales_case_event_insert_policy ON sales_case_event FOR INSERT TO employee
    WITH CHECK (true);

COMMIT;
