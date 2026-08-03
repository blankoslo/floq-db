-- Revert floq:alter_table_customers_add_tripletex_attn_id from pg

BEGIN;

ALTER TABLE customers
  DROP COLUMN tripletex_attn_id;

COMMIT;
