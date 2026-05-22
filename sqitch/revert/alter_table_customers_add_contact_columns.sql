-- Revert floq:alter_table_customers_add_contact_columns from pg

BEGIN;

ALTER TABLE customers
  DROP COLUMN is_subcontractor,
  DROP COLUMN account_manager,
  DROP COLUMN tripletex_contact_id;

COMMIT;
