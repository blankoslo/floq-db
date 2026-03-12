-- Revert floq:add_employee_tenure_role_table from pg

BEGIN;

DROP TABLE IF EXISTS employee_tenure_role;

COMMIT;
