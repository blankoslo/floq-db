-- Revert floq:add_employee_tenure_role_table from pg

BEGIN;

DROP POLICY IF EXISTS employee_tenure_role_select_policy ON employee_tenure_role;
DROP POLICY IF EXISTS employee_tenure_role_write_policy ON employee_tenure_role;
DROP TABLE IF EXISTS employee_tenure_role;

COMMIT;
