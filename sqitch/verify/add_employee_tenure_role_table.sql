-- Verify floq:add_employee_tenure_role_table on pg

BEGIN;

SELECT * FROM employee_tenure_role;

-- divide-by-zero if policy does not exist
SELECT 1/COUNT(*) FROM pg_catalog.pg_policies WHERE tablename = 'employee_tenure_role';

ROLLBACK;
