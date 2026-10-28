-- Verify floq:add_ledger_expenses on pg

BEGIN;

DO
$$
DECLARE
    ledger_tables CONSTANT TEXT[] := ARRAY[
        'ledger_expense', 'ledger_tech_expense', 'ledger_social_expense', 'ledger_fagutvikling_expense',
        'ledger_fagutvikling_participant', 'ledger_expense_draft', 'ledger_receipt'
    ];
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
        WHERE conrelid = 'ledger_receipt'::regclass
          AND conname = 'ledger_receipt_has_one_owner'
          AND contype = 'c'
    ) THEN
        RAISE EXCEPTION 'a receipt can belong to both a draft and an expense, or to neither';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_trigger
        WHERE NOT tgisinternal
          AND tgname IN ('ledger_expense_created_by', 'ledger_receipt_created_by')
    ) <> 2 THEN
        RAISE EXCEPTION 'the created_by triggers are missing';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_class
        WHERE relname = ANY (ledger_tables)
          AND relrowsecurity
    ) <> 7 THEN
        RAISE EXCEPTION 'row-level security is not enabled on every ledger table';
    END IF;

    -- Without SECURITY DEFINER the type tables' policies recurse into each other.
    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_proc
        WHERE proname IN ('ledger_expense_visible', 'ledger_expense_editable')
          AND prosecdef
    ) <> 2 THEN
        RAISE EXCEPTION 'the ledger access functions are not SECURITY DEFINER';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename = 'ledger_expense_draft'
          AND NOT (roles = ARRAY['employee']::name[] AND qual = '(owner_id = logged_in_employee_id())')
    ) THEN
        RAISE EXCEPTION 'someone other than its owner can reach a draft';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(ledger_tables) AS t
        WHERE NOT has_table_privilege('employee', t, 'SELECT, INSERT, UPDATE, DELETE')
    ) THEN
        RAISE EXCEPTION 'employee grants do not match the expected contract';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(ledger_tables) AS t
        WHERE t <> 'ledger_expense_draft'
          AND NOT has_table_privilege('read_only', t, 'SELECT')
    ) OR has_table_privilege('read_only', 'ledger_expense_draft', 'SELECT')
       OR has_table_privilege('read_only', 'ledger_expense', 'INSERT')
       OR has_table_privilege('read_only', 'ledger_expense', 'UPDATE')
       OR has_table_privilege('read_only', 'ledger_expense', 'DELETE') THEN
        RAISE EXCEPTION 'read_only grants do not match the expected contract';
    END IF;
END;
$$;

ROLLBACK;
