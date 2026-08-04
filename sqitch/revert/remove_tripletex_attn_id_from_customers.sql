-- Revert floq:remove_tripletex_attn_id_from_customers from pg

BEGIN;

ALTER TABLE customers
  ADD COLUMN tripletex_attn_id integer;

COMMIT;
