-- Revert floq:add_staffing_week from pg

BEGIN;

DROP TABLE staffing_week;

COMMIT;
