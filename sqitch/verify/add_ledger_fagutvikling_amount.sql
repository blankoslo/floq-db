-- Verify floq:add_ledger_fagutvikling_amount on pg

BEGIN;

DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_fagutvikling_expense'
          AND column_name = 'amount'
          AND data_type = 'numeric'
          AND numeric_precision = 12
          AND numeric_scale = 2
    ) THEN
        RAISE EXCEPTION 'ledger_fagutvikling_expense should have a numeric(12, 2) amount';
    END IF;

    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_fagutvikling_expense'
          AND is_nullable = 'YES'
    ) IS DISTINCT FROM ARRAY['accommodation', 'amount', 'location', 'role', 'ticket', 'travel'] THEN
        RAISE EXCEPTION 'only amount, location, role, ticket, travel and accommodation may be null on ledger_fagutvikling_expense';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'ledger_fagutvikling_expense'::regclass
          AND contype = 'c'
          AND conname IN ('ledger_fagutvikling_expense_amount_positive', 'ledger_fagutvikling_expense_basic_or_costed')
    ) <> 2 THEN
        RAISE EXCEPTION 'a fagutvikling can have a non-positive amount, or be half basic and half costed';
    END IF;
END;
$$;

ROLLBACK;
