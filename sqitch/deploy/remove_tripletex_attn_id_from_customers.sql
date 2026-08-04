-- Deploy floq:remove_tripletex_attn_id_from_customers to pg
-- requires: alter_table_customers_add_tripletex_attn_id

BEGIN;

ALTER TABLE customers
  DROP COLUMN tripletex_attn_id;

COMMIT;
