BEGIN;

INSERT INTO staffing (employee, project, date, percentage)
SELECT 
    employee_id, 
    reason,
    date, 
    percentage
FROM absence
JOIN absence_reasons 
    ON absence.reason = absence_reasons.id;

-- Delete the same rows from absence
DELETE FROM absence
USING absence_reasons
WHERE absence.reason = absence_reasons.id;

COMMIT;
