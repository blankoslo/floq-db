BEGIN;

INSERT INTO absence (employee_id, date, reason, percentage)
SELECT 
    employee, 
    date, 
    project,
    percentage
FROM staffing
JOIN absence_reasons 
    ON staffing.project = absence_reasons.id
ON CONFLICT (employee_id, reason, date) DO NOTHING;


-- Delete the same rows from staffing
DELETE FROM staffing
USING absence_reasons
WHERE staffing.project = absence_reasons.id;

COMMIT;
