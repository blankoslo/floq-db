BEGIN;

ALTER TABLE sales_candidate
    ADD COLUMN awarded    BOOLEAN     NOT NULL DEFAULT FALSE,
    ADD COLUMN awarded_at TIMESTAMPTZ;

INSERT INTO sales_event_kind (slug, label) VALUES
    ('candidate_awarded',   'Fikk oppdraget'),
    ('candidate_unawarded', 'Fikk ikke oppdraget likevel');

CREATE FUNCTION set_sales_candidate_awarded_at()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF NOT NEW.awarded THEN
        NEW.awarded_at = NULL;
    ELSIF TG_OP = 'INSERT' OR NOT OLD.awarded THEN
        NEW.awarded_at = now();
    ELSE
        NEW.awarded_at = OLD.awarded_at;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER sales_candidate_awarded_at
    BEFORE INSERT OR UPDATE ON sales_candidate
    FOR EACH ROW
    EXECUTE FUNCTION set_sales_candidate_awarded_at();

CREATE FUNCTION log_sales_candidate_award_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    kind          TEXT;
    case_row      sales_case;
    person_name   TEXT;
    customer_name TEXT;
BEGIN
    IF NEW.awarded THEN
        kind = 'candidate_awarded';
    ELSE
        kind = 'candidate_unawarded';
    END IF;

    SELECT * INTO case_row FROM sales_case c WHERE c.id = NEW.case_id;

    SELECT coalesce(em.first_name || ' ' || em.last_name, p.name_text)
    INTO person_name
    FROM person_card p
    LEFT JOIN employees em ON em.id = p.employee_id
    WHERE p.id = NEW.person_id;

    SELECT coalesce(cu.name, case_row.customer_text, case_row.customer_id)
    INTO customer_name
    FROM (SELECT 1) AS one
    LEFT JOIN customers cu ON cu.id::TEXT = case_row.customer_id;

    INSERT INTO sales_case_event (case_id, kind_slug, payload)
    VALUES (NEW.case_id, kind, jsonb_build_object('personId', NEW.person_id, 'name', person_name));

    INSERT INTO person_card_event (card_id, kind_slug, payload)
    VALUES (NEW.person_id, kind,
            jsonb_build_object('caseId', NEW.case_id, 'customer', customer_name, 'role', case_row.role));

    RETURN NULL;
END;
$$;

CREATE TRIGGER sales_candidate_award_change
    AFTER UPDATE OF awarded ON sales_candidate
    FOR EACH ROW
    WHEN (NEW.awarded IS DISTINCT FROM OLD.awarded)
    EXECUTE FUNCTION log_sales_candidate_award_change();

GRANT UPDATE (awarded) ON TABLE sales_candidate TO employee;

CREATE POLICY sales_candidate_update_policy ON sales_candidate FOR UPDATE TO employee
    USING (true) WITH CHECK (true);

COMMIT;
