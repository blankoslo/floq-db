-- Verify floq:absence_table on pg

BEGIN;

SELECT is_holiday(current_date);
SELECT is_absence_reason('AVS');
SELECT * FROM absence_reasons WHERE false;
SELECT employee_id, date, reason FROM absence WHERE false;

ROLLBACK;
