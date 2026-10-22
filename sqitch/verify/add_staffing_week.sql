-- Verify floq:add_staffing_week on pg

BEGIN;

SELECT employee, project, week_start, percentage FROM staffing_week WHERE FALSE;

ROLLBACK;
