BEGIN;

CREATE TABLE sales_candidate (
    case_id    TEXT        NOT NULL REFERENCES sales_case (id) ON DELETE CASCADE,
    person_id  TEXT        NOT NULL REFERENCES person_card (id) ON DELETE CASCADE,
    created_by INTEGER     REFERENCES employees (id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT sales_candidate_pkey PRIMARY KEY (case_id, person_id)
);

CREATE INDEX sales_candidate_person_idx ON sales_candidate (person_id);

INSERT INTO sales_event_kind (slug, label) VALUES
    ('candidate_added',   'Lagt til som kandidat'),
    ('candidate_removed', 'Fjernet som kandidat');

CREATE FUNCTION set_sales_candidate_author()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.created_by = logged_in_employee_id();
    RETURN NEW;
END;
$$;

CREATE TRIGGER sales_candidate_author
    BEFORE INSERT ON sales_candidate
    FOR EACH ROW
    EXECUTE FUNCTION set_sales_candidate_author();

CREATE FUNCTION log_sales_candidate_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    pair          sales_candidate;
    kind          TEXT;
    case_row      JSONB;
    person_row    JSONB;
    case_alive    BOOLEAN;
    person_alive  BOOLEAN;
    person_name   TEXT;
    customer_name TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        pair = NEW;
        kind = 'candidate_added';
    ELSE
        pair = OLD;
        kind = 'candidate_removed';
    END IF;

    SELECT to_jsonb(c) INTO case_row FROM sales_case c WHERE c.id = pair.case_id;
    case_alive = case_row IS NOT NULL;

    SELECT to_jsonb(p) INTO person_row FROM person_card p WHERE p.id = pair.person_id;
    person_alive = person_row IS NOT NULL;

    IF NOT case_alive THEN
        SELECT e.payload -> 'case'
        INTO case_row
        FROM sales_case_event e
        WHERE e.kind_slug = 'deleted'
          AND e.payload -> 'case' ->> 'id' = pair.case_id
        ORDER BY e.occurred_at DESC
        LIMIT 1;
    END IF;

    IF NOT person_alive THEN
        SELECT e.payload -> 'card'
        INTO person_row
        FROM person_card_event e
        WHERE e.kind_slug = 'deleted'
          AND e.payload -> 'card' ->> 'id' = pair.person_id
        ORDER BY e.occurred_at DESC
        LIMIT 1;
    END IF;

    IF case_alive THEN
        SELECT coalesce(em.first_name || ' ' || em.last_name, person_row ->> 'name_text')
        INTO person_name
        FROM (SELECT 1) AS one
        LEFT JOIN employees em ON em.id = (person_row ->> 'employee_id')::INTEGER;

        INSERT INTO sales_case_event (case_id, kind_slug, payload)
        VALUES (pair.case_id, kind, jsonb_build_object('personId', pair.person_id, 'name', person_name));
    END IF;

    IF person_alive THEN
        SELECT coalesce(cu.name, case_row ->> 'customer_text', case_row ->> 'customer_id')
        INTO customer_name
        FROM (SELECT 1) AS one
        LEFT JOIN customers cu ON cu.id::TEXT = case_row ->> 'customer_id';

        INSERT INTO person_card_event (card_id, kind_slug, payload)
        VALUES (pair.person_id, kind,
                jsonb_build_object('caseId', pair.case_id, 'customer', customer_name, 'role', case_row ->> 'role'));
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER sales_candidate_added
    AFTER INSERT ON sales_candidate
    FOR EACH ROW
    EXECUTE FUNCTION log_sales_candidate_change();

CREATE TRIGGER sales_candidate_removed
    AFTER DELETE ON sales_candidate
    FOR EACH ROW
    EXECUTE FUNCTION log_sales_candidate_change();

GRANT SELECT, INSERT, DELETE ON TABLE sales_candidate TO employee;
GRANT SELECT ON TABLE sales_candidate TO read_only;

ALTER TABLE sales_candidate ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_candidate_select_policy ON sales_candidate FOR SELECT USING (true);
CREATE POLICY sales_candidate_insert_policy ON sales_candidate FOR INSERT TO employee WITH CHECK (true);
CREATE POLICY sales_candidate_delete_policy ON sales_candidate FOR DELETE TO employee USING (true);

COMMIT;
