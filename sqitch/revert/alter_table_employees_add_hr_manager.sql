-- Revert floq:alter_table_employees_add_hr_manager from pg

BEGIN;

ALTER TABLE employees
    DROP COLUMN hr_manager;
    REVOKE SELECT, INSERT, UPDATE ON employees FROM employee;

COMMIT;
