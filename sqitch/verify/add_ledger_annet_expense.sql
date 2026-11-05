-- Verify floq:add_ledger_annet_expense on pg

BEGIN;

DO
$$
BEGIN
    IF enum_range(NULL::ledger_expense_type)::TEXT[] IS DISTINCT FROM ARRAY['tech', 'fagutvikling', 'annet'] THEN
        RAISE EXCEPTION 'ledger_expense_type should be tech, fagutvikling and annet';
    END IF;

    IF to_regtype('ledger_expense_type_old') IS NOT NULL THEN
        RAISE EXCEPTION 'ledger_expense_type_old is still there';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_annet_expense'
          AND (column_name, data_type, is_nullable) IN (
              ('expense_id', 'text', 'NO'),
              ('type', 'USER-DEFINED', 'NO'),
              ('amount', 'numeric', 'NO'),
              ('cost_category', 'text', 'YES')
          )
    ) <> 4 THEN
        RAISE EXCEPTION 'ledger_annet_expense should have expense_id, type, amount and a nullable cost_category';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE contype = 'f'
          AND confrelid = 'ledger_expense'::regclass
          AND confdeltype = 'c'
          AND array_length(conkey, 1) = 2
          AND conrelid IN (
              'ledger_tech_expense'::regclass,
              'ledger_fagutvikling_expense'::regclass,
              'ledger_annet_expense'::regclass
          )
    ) <> 3 THEN
        RAISE EXCEPTION 'a type table does not follow its expense by (id, type)';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE contype = 'c'
          AND conname IN (
              'ledger_tech_expense_is_tech',
              'ledger_fagutvikling_expense_is_fagutvikling',
              'ledger_annet_expense_is_annet'
          )
    ) <> 3 THEN
        RAISE EXCEPTION 'a type table no longer checks its type';
    END IF;
END;
$$;

ROLLBACK;
