-- Verify floq:remove_tripletex_attn_id_from_customers on pg

BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'customers'
          AND column_name = 'tripletex_attn_id'
    ) THEN
        RAISE EXCEPTION 'tripletex_attn_id column still exists on customers';
    END IF;
END $$;

ROLLBACK;
