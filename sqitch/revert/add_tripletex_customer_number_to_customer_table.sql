-- Revert floq:add_tripletex_customer_number_to_customer_table from pg

BEGIN;

ALTER TABLE customers DROP COLUMN tripletex_number;

COMMIT;
