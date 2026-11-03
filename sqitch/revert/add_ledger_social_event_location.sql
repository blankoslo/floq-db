-- Revert floq:add_ledger_social_event_location from pg

BEGIN;

ALTER TABLE ledger_social_event DROP COLUMN location;

COMMIT;
