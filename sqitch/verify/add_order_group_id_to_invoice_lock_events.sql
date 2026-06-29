-- Verify floq:add_order_group_id_to_invoice_lock_events on pg

BEGIN;

SELECT order_group_id FROM invoice_lock_events;

ROLLBACK;
