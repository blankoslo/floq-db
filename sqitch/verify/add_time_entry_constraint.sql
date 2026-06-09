-- Verify floq:add_time_entry_constraint on pg

BEGIN;

SELECT 1 FROM pg_constraint WHERE conname = 'time_entry_employee_project_date_key' AND contype = 'u';

ROLLBACK;
