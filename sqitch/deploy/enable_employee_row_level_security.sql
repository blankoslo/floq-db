-- Deploy floq:enable_employee_row_level_security from pg
-- requires: add_employee_user

CREATE OR REPLACE FUNCTION check_employee_write_access(editing_employee_id INTEGER)
    RETURNS BOOL
AS
$$
DECLARE
    logged_in_employee_id INTEGER := NULL;
    is_admin              BOOL    := NULL;
BEGIN
    SELECT id FROM employees WHERE email = current_setting('request.jwt.claims')::json->>'email' INTO logged_in_employee_id;
    SELECT COUNT(*) > 0 FROM employee_role WHERE employee_id = logged_in_employee_id AND role_type = 'admin' INTO is_admin;

    IF is_admin THEN
        RETURN TRUE;
    END IF;

    RETURN editing_employee_id = logged_in_employee_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_admin_write_access()
    RETURNS BOOL
AS
$$
DECLARE
    logged_in_employee_id INTEGER := NULL;
    is_admin              BOOL    := NULL;
BEGIN
    SELECT id FROM employees WHERE email = current_setting('request.jwt.claims')::json->>'email' INTO logged_in_employee_id;
    SELECT COUNT(*) > 0 FROM employee_role WHERE employee_id = logged_in_employee_id AND role_type = 'admin' INTO is_admin;

    RETURN is_admin;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enable_default_row_level_security(tablename REGCLASS, check_function TEXT)
    RETURNS VOID
AS
$$
DECLARE
    select_policy TEXT := CONCAT(tablename, '_select_policy');
    write_policy  TEXT := CONCAT(tablename, '_write_policy');
BEGIN
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', tablename);

    -- Everyone can read everything
    EXECUTE format('DROP POLICY IF EXISTS %s ON %s',
                   select_policy, tablename);
    EXECUTE format('CREATE POLICY %s ON %s FOR SELECT USING (true)',
                   select_policy, tablename);

    -- Employees can only create/ edit/ delete their own entries, admins can for everything
    EXECUTE format('DROP POLICY IF EXISTS %s ON %s',
                   write_policy, tablename);
    EXECUTE format('CREATE POLICY %s ON %s FOR ALL TO employee USING (%s) WITH CHECK (%s)',
                   write_policy, tablename, check_function, check_function);
END;
$$ LANGUAGE plpgsql;

SELECT enable_default_row_level_security('absence', 'check_employee_write_access(employee_id)');
SELECT enable_default_row_level_security('employees',  'check_employee_write_access(id)');
SELECT enable_default_row_level_security('paid_overtime',  'check_employee_write_access(employee)');
SELECT enable_default_row_level_security('time_entry',  'check_employee_write_access(employee)');

SELECT enable_default_row_level_security('holidays', 'check_admin_write_access()');
SELECT enable_default_row_level_security('invoice_balance', 'check_admin_write_access()');
SELECT enable_default_row_level_security('timelock_events', 'check_admin_write_access()');
SELECT enable_default_row_level_security('vacation_days', 'check_admin_write_access()');
