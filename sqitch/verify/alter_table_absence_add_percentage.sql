-- Verify floq:alter_table_absence_add_percentage on pg

BEGIN;

SELECT employee_id, date, percentage FROM absence WHERE FALSE;

ROLLBACK;
