-- Verify floq:add_staffing_periods_table on pg

BEGIN;

SELECT * FROM staffing_periods WHERE FALSE;

ROLLBACK;
