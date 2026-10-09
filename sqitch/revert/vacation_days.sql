-- Revert floq:vacation_days from pg

BEGIN;

DROP VIEW vacation_days_by_year;
DROP VIEW vacation_days_spent;
DROP VIEW vacation_days_earnt;
DROP VIEW employee_years;
DROP TABLE vacation_days;

COMMIT;
