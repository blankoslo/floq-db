-- Revert floq:add_staffing_events from pg

BEGIN;

DROP TRIGGER staffing_event ON staffing;
DROP FUNCTION log_staffing_event();
DROP TABLE staffing_events;

COMMIT;
