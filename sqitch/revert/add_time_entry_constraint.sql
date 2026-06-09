-- Revert floq:add_time_entry_constraint from pg

BEGIN;

ALTER TABLE time_entry DROP CONSTRAINT IF EXISTS time_entry_employee_project_date_key;

COMMIT;
