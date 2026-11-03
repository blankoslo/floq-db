-- Revert floq:add_ledger_social_events from pg

BEGIN;

DROP TABLE ledger_social_event_utgift;
DROP TABLE ledger_social_event;

COMMIT;
