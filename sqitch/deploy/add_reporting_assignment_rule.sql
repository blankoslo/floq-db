BEGIN;

CREATE TABLE reporting_assignment_rule (
    id                 INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    minimum_percentage INTEGER NOT NULL DEFAULT 60 CHECK (minimum_percentage BETWEEN 1 AND 100),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by         INTEGER REFERENCES employees(id) ON DELETE SET NULL
);

INSERT INTO reporting_assignment_rule DEFAULT VALUES;

GRANT SELECT ON TABLE reporting_assignment_rule TO employee;
GRANT UPDATE (minimum_percentage) ON TABLE reporting_assignment_rule TO employee;
GRANT SELECT ON TABLE reporting_assignment_rule TO read_only;

SELECT enable_default_row_level_security('reporting_assignment_rule', 'check_admin_write_access()');

CREATE FUNCTION set_reporting_assignment_rule_metadata()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.updated_at = clock_timestamp();

    SELECT id
    INTO NEW.updated_by
    FROM employees
    WHERE email = current_setting('request.jwt.claims', true)::json ->> 'email';

    RETURN NEW;
END;
$$;

CREATE TRIGGER reporting_assignment_rule_metadata
    BEFORE UPDATE ON reporting_assignment_rule
    FOR EACH ROW
    EXECUTE FUNCTION set_reporting_assignment_rule_metadata();

COMMIT;
