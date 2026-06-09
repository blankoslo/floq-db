-- Deploy floq:add_time_entry_constraint to pg

BEGIN;

 ALTER TABLE time_entry
    ADD CONSTRAINT time_entry_employee_project_date_key
    UNIQUE (employee, project, date);

COMMIT;
