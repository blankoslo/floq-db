-- Revert floq:widen_tripletex_ids_to_bigint from pg

BEGIN;

-- Fails if any row already holds a value outside the int4 range by this point.
ALTER TABLE invoice_lock_events
  ALTER COLUMN order_id TYPE integer,
  ALTER COLUMN order_group_id TYPE integer;

ALTER TABLE customers
  ALTER COLUMN tripletex_contact_id TYPE integer;

ALTER TABLE projects
  ALTER COLUMN tripletex_contact_id TYPE integer,
  ALTER COLUMN tripletex_attn_id TYPE integer;

COMMIT;
