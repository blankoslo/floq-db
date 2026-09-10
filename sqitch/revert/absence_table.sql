-- Revert floq:absence_table from pg

BEGIN;

INSERT INTO staffing (employee, date, project)
  ( SELECT employee_id as employee, date, reason as project
      FROM absence
  );

DROP TABLE absence CASCADE;
DROP VIEW absence_reasons;
DROP FUNCTION is_absence_reason(text);
DROP FUNCTION is_holiday(date);

COMMIT;
