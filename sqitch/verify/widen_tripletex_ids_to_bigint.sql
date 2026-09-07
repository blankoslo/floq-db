-- Verify floq:widen_tripletex_ids_to_bigint on pg

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE (table_name, column_name, data_type) IN (
      ('invoice_lock_events', 'order_id', 'integer'),
      ('invoice_lock_events', 'order_group_id', 'integer'),
      ('customers', 'tripletex_contact_id', 'integer'),
      ('projects', 'tripletex_contact_id', 'integer'),
      ('projects', 'tripletex_attn_id', 'integer')
    )
  ) THEN
    RAISE EXCEPTION 'Expected order_id/order_group_id/tripletex_contact_id/tripletex_attn_id to be bigint';
  END IF;
END $$;

ROLLBACK;
