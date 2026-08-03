-- Deploy floq:alter_table_customers_add_tripletex_attn_id to pg

BEGIN;

ALTER TABLE customers
  ADD COLUMN tripletex_attn_id integer;

COMMIT;