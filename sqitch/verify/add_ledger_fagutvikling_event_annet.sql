-- Verify floq:add_ledger_fagutvikling_event_annet on pg

BEGIN;

DO
$$
BEGIN
    IF enum_range(NULL::ledger_fagutvikling_cost)::TEXT[]
        IS DISTINCT FROM ARRAY['ticket', 'travel', 'accommodation', 'annet'] THEN
        RAISE EXCEPTION 'ledger_fagutvikling_cost should be ticket, travel, accommodation and annet';
    END IF;

    IF to_regtype('ledger_fagutvikling_cost_old') IS NOT NULL THEN
        RAISE EXCEPTION 'ledger_fagutvikling_cost_old is still there';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_fagutvikling_event_expense'
          AND column_name = 'cost'
          AND udt_name = 'ledger_fagutvikling_cost'
    ) THEN
        RAISE EXCEPTION 'ledger_fagutvikling_event_expense.cost should be a ledger_fagutvikling_cost';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_fagutvikling_event_expense'
          AND column_name = 'cost_category'
          AND data_type = 'text'
    ) THEN
        RAISE EXCEPTION 'ledger_fagutvikling_event_expense should have a text cost_category';
    END IF;

    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_fagutvikling_event_expense'
          AND is_nullable = 'YES'
    ) IS DISTINCT FROM ARRAY['cost_category', 'tripletex_expense_id'] THEN
        RAISE EXCEPTION 'only cost_category and tripletex_expense_id may be null on ledger_fagutvikling_event_expense';
    END IF;

    IF (
        SELECT array_agg(conname::TEXT || ':' || contype::TEXT ORDER BY conname)
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'ledger_fagutvikling_event_expense'::regclass
          AND contype IN ('c', 'u')
    ) IS DISTINCT FROM ARRAY[
        'ledger_fagutvikling_event_expense_amount_positive:c',
        'ledger_fagutvikling_event_expense_cost_category_on_annet_utlegg:c',
        'ledger_fagutvikling_event_expense_tripletex_expense_id_key:u',
        'ledger_fagutvikling_event_expense_utlegg_or_annet:c'
    ] THEN
        RAISE EXCEPTION 'only an annet may lack an utlegg, and only an annet''s utlegg has a cost category';
    END IF;
END;
$$;

ROLLBACK;
