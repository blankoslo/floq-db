-- Verify floq:alter_table_staffing_add_staffing_percentage on pg

BEGIN;

SELECT employee, date, percentage FROM staffing WHERE FALSE;

ROLLBACK;
