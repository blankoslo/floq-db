-- Deploy floq:compact_time_entries to pg

BEGIN;

-- Update the most-recently-created row for each (employee, date, project)
-- with the summed minutes for that group
UPDATE time_entry te
SET minutes = subq.total_minutes
FROM (
    SELECT DISTINCT ON (employee, date, project)
        id,
        SUM(minutes) OVER (PARTITION BY employee, date, project) AS total_minutes
    FROM time_entry
    ORDER BY employee, date, project, created DESC
) subq
WHERE te.id = subq.id;

-- Delete all non-keeper rows
DELETE FROM time_entry
WHERE id NOT IN (
    SELECT DISTINCT ON (employee, date, project) id
    FROM time_entry
    ORDER BY employee, date, project, created DESC
);

-- Enforce one row per (employee, date, project) going forward
ALTER TABLE time_entry
    ADD CONSTRAINT time_entry_employee_date_project_unique
    UNIQUE (employee, date, project);

COMMIT;
