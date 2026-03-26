-- Revert floq:compact_time_entries from pg
-- NOTE: The data compaction (row deletion) is irreversible.
-- This revert only removes the UNIQUE constraint.

BEGIN;

ALTER TABLE time_entry
    DROP CONSTRAINT time_entry_employee_date_project_unique;

COMMIT;
