-- Revert floq:add_invoice_lock_events_table from pg

BEGIN;

DROP TABLE invoice_lock_events;

COMMIT;
