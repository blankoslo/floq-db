-- Revert floq:add_staffing_periods_table from pg

BEGIN;

DROP TABLE staffing_periods;

COMMIT;
