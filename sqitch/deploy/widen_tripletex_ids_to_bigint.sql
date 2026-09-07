-- Deploy floq:widen_tripletex_ids_to_bigint to pg
-- requires: add_invoice_lock_events_table
-- requires: add_order_group_id_to_invoice_lock_events
-- requires: alter_table_customers_add_contact_columns
-- requires: alter_projects_table
-- requires: add_tripletex_attn_id_to_projects

BEGIN;

ALTER TABLE invoice_lock_events
  ALTER COLUMN order_id TYPE bigint,
  ALTER COLUMN order_group_id TYPE bigint;

ALTER TABLE customers
  ALTER COLUMN tripletex_contact_id TYPE bigint;

ALTER TABLE projects
  ALTER COLUMN tripletex_contact_id TYPE bigint,
  ALTER COLUMN tripletex_attn_id TYPE bigint;

COMMIT;
