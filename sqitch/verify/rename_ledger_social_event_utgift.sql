-- Verify floq:rename_ledger_social_event_utgift on pg

BEGIN;

DO
$$
BEGIN
    IF to_regclass('public.ledger_social_event_utgift') IS NOT NULL
        OR to_regclass('public.ledger_social_event_expense') IS NULL THEN
        RAISE EXCEPTION 'ledger_social_event_utgift has not been renamed to ledger_social_event_expense';
    END IF;

    IF (
        SELECT array_agg(conname::TEXT || ':' || contype::TEXT ORDER BY conname)
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'ledger_social_event_expense'::regclass
          AND contype IN ('c', 'f', 'p', 'u')
    ) IS DISTINCT FROM ARRAY['ledger_social_event_expense_added_by_fkey:f',
                             'ledger_social_event_expense_amount_positive:c',
                             'ledger_social_event_expense_event_id_fkey:f',
                             'ledger_social_event_expense_pkey:p',
                             'ledger_social_event_expense_tripletex_expense_id_key:u'] THEN
        RAISE EXCEPTION 'ledger_social_event_expense constraints are not all renamed with it';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class
        WHERE relnamespace = 'public'::regnamespace
          AND relname LIKE 'ledger\_social\_event\_utgift%'
    ) THEN
        RAISE EXCEPTION 'an index still has the old ledger_social_event_utgift name';
    END IF;

    IF NOT has_table_privilege('employee', 'ledger_social_event_expense', 'SELECT, INSERT, UPDATE, DELETE') THEN
        RAISE EXCEPTION 'employee cannot read and write ledger_social_event_expense';
    END IF;
END;
$$;

ROLLBACK;
