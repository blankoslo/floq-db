-- Deploy floq:add_tripletex_customer_number_to_customer_table to pg

BEGIN;

ALTER TABLE customers ADD COLUMN tripletex_number INTEGER UNIQUE;

COMMIT;
