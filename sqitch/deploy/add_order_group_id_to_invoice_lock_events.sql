-- Deploy floq:add_order_group_id_to_invoice_lock_events to pg
-- requires: add_invoice_lock_events_table

BEGIN;

ALTER TABLE invoice_lock_events ADD COLUMN order_group_id INTEGER;

COMMIT;
