-- Verify floq:drop_ledger_social_expense on pg

BEGIN;

DO
$$
BEGIN
    IF to_regclass('public.ledger_social_expense') IS NOT NULL THEN
        RAISE EXCEPTION 'ledger_social_expense is still there';
    END IF;

    IF enum_range(NULL::ledger_expense_type)::TEXT[] IS DISTINCT FROM ARRAY['tech', 'fagutvikling'] THEN
        RAISE EXCEPTION 'ledger_expense_type should be tech and fagutvikling alone';
    END IF;

    IF to_regtype('ledger_expense_type_old') IS NOT NULL THEN
        RAISE EXCEPTION 'ledger_expense_type_old is still there';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE contype = 'f'
          AND confrelid = 'ledger_expense'::regclass
          AND confdeltype = 'c'
          AND array_length(conkey, 1) = 2
          AND conrelid IN ('ledger_tech_expense'::regclass, 'ledger_fagutvikling_expense'::regclass)
    ) <> 2 THEN
        RAISE EXCEPTION 'a type table does not follow its expense by (id, type)';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE contype = 'c'
          AND conname IN ('ledger_tech_expense_is_tech', 'ledger_fagutvikling_expense_is_fagutvikling')
    ) <> 2 THEN
        RAISE EXCEPTION 'a type table no longer checks its type';
    END IF;
END;
$$;

ROLLBACK;
