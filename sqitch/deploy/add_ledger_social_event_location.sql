-- Deploy floq:add_ledger_social_event_location to pg
-- requires: add_ledger_social_events

BEGIN;

ALTER TABLE ledger_social_event ADD COLUMN location TEXT;

COMMIT;
