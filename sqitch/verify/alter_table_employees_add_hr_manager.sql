-- Verify floq:alter_table_employees_add_hr_manager on pg

BEGIN;

SELECT hr_manager FROM employees;

ROLLBACK;
