-- Revert floq:add_order_group_id_to_invoice_lock_events from pg

BEGIN;

ALTER TABLE invoice_lock_events DROP COLUMN order_group_id;

COMMIT;
