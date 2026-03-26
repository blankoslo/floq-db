-- Verify floq:compact_time_entries on pg

BEGIN;

-- Verify the unique constraint exists (fails with division-by-zero if missing)
SELECT 1 / COUNT(*)
FROM pg_catalog.pg_constraint
WHERE conname = 'time_entry_employee_date_project_unique';

-- Verify no duplicate (employee, date, project) groups remain
SELECT 1 / CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM (
    SELECT employee, date, project
    FROM time_entry
    GROUP BY employee, date, project
    HAVING COUNT(*) > 1
) duplicates;

ROLLBACK;
