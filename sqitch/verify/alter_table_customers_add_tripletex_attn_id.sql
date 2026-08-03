-- Verify floq:alter_table_customers_add_tripletex_attn_id on pg

BEGIN;

SELECT tripletex_attn_id FROM customers;

ROLLBACK;
