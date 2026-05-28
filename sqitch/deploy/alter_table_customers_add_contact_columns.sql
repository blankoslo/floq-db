-- Deploy floq:alter_table_customers_add_contact_columns to pg
-- requires: time_tracking_tables
-- requires: employees_table
-- requires: add_tripletex_customer_number_to_customer_table

BEGIN;

ALTER TABLE customers
  ADD COLUMN account_manager      integer REFERENCES employees(id),
  ADD COLUMN tripletex_contact_id integer;

COMMIT;
