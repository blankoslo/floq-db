-- Verify floq:add_invoice_lock_events_table on pg

BEGIN;

SELECT id, project_id, creator_id, created_at, order_id, commit_date FROM invoice_lock_events;

ROLLBACK;
