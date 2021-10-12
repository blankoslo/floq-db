-- Deploy floq:alter_table_employees_add_hr_manager to pg

BEGIN;

ALTER TABLE employees
    ADD COLUMN hr_manager INTEGER REFERENCES employees(id) ON UPDATE NO ACTION ON DELETE SET NULL;
    GRANT SELECT, INSERT, UPDATE ON employees TO employee;

COMMIT;
-- 