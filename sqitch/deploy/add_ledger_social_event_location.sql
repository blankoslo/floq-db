-- Deploy floq:add_ledger_social_event_location to pg
-- requires: add_ledger_social_events

BEGIN;

-- Where it took place. The ledger API requires one on every event it records; null only on those
-- from before it was asked.
ALTER TABLE ledger_social_event ADD COLUMN location TEXT;

COMMIT;
