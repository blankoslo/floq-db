-- Verify floq:add_ledger_expenses on pg

BEGIN;

DO
$$
BEGIN
    IF enum_range(NULL::ledger_expense_type)::TEXT[] <> ARRAY['tech', 'fagutvikling', 'sosialt'] THEN
        RAISE EXCEPTION 'ledger_expense_type does not match the app''s type keys';
    END IF;

    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_expense'
    ) <> ARRAY['charge_to_project', 'comment', 'created_at', 'created_by', 'date', 'description', 'id',
               'paid_by', 'tripletex_expense_id', 'type'] THEN
        RAISE EXCEPTION 'ledger_expense columns do not match the expected contract';
    END IF;

    -- Each type table points at (id, type), which is what stops a row hanging off an
    -- expense of another type.
    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE contype = 'f'
          AND confrelid = 'ledger_expense'::regclass
          AND confdeltype = 'c'
          AND array_length(conkey, 1) = 2
          AND conrelid IN ('ledger_tech_expense'::regclass, 'ledger_social_expense'::regclass,
                           'ledger_fagutvikling_expense'::regclass)
    ) <> 3 THEN
        RAISE EXCEPTION 'a type table does not follow its expense by (id, type)';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'ledger_fagutvikling_participant'::regclass
          AND contype = 'f'
          AND confrelid = 'ledger_fagutvikling_expense'::regclass
          AND confdeltype = 'c'
    ) THEN
        RAISE EXCEPTION 'participants do not follow their fagutvikling expense';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(ARRAY['ledger_expense', 'ledger_tech_expense', 'ledger_social_expense',
                          'ledger_fagutvikling_expense', 'ledger_fagutvikling_participant']) AS t
        WHERE NOT has_table_privilege('employee', t, 'SELECT, INSERT, UPDATE, DELETE')
    ) THEN
        RAISE EXCEPTION 'employee cannot read and write every ledger table';
    END IF;
END;
$$;

ROLLBACK;
