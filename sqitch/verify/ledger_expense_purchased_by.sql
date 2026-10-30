-- Verify floq:ledger_expense_purchased_by on pg

DO $$
BEGIN
    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_expense'
          AND column_name IN ('paid_by', 'purchased_by', 'created_by')
    ) IS DISTINCT FROM ARRAY['purchased_by'] THEN
        RAISE EXCEPTION 'ledger_expense should have purchased_by, and neither paid_by nor created_by';
    END IF;
END $$;
