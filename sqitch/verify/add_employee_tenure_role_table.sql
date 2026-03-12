-- Verify floq:add_employee_tenure_role_table on pg

BEGIN;

SELECT * FROM employee_tenure_role;

ROLLBACK;
