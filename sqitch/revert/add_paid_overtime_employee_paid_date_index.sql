-- Revert floq:add_paid_overtime_employee_paid_date_index from pg

BEGIN;

DROP INDEX IF EXISTS paid_overtime_employee_paid_date_index;

COMMIT;
