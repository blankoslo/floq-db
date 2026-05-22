-- Verify floq:alter_table_customers_add_contact_columns on pg

BEGIN;

SELECT is_subcontractor, account_manager, tripletex_contact_id FROM customers;

ROLLBACK;
