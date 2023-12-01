-- Revert floq:change_jwt_claim_retrieval from pg

BEGIN;

CREATE OR REPLACE FUNCTION check_employee_write_access(editing_employee_id INTEGER)
    RETURNS BOOL
AS
$$
DECLARE
    logged_in_employee_id INTEGER := NULL;
    is_admin              BOOL    := NULL;
BEGIN
    SELECT id FROM employees WHERE email = current_setting('request.jwt.claim.email') INTO logged_in_employee_id;
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
    SELECT id FROM employees WHERE email = current_setting('request.jwt.claim.email') INTO logged_in_employee_id;
    SELECT COUNT(*) > 0 FROM employee_role WHERE employee_id = logged_in_employee_id AND role_type = 'admin' INTO is_admin;

    RETURN is_admin;
END;
$$ LANGUAGE plpgsql;

COMMIT;
