-- Verify floq:move_fagutvikling_participant_to_expense on pg

BEGIN;

DO
$$
BEGIN
    IF to_regclass('public.ledger_fagutvikling_participant') IS NOT NULL THEN
        RAISE EXCEPTION 'ledger_fagutvikling_participant is still there';
    END IF;

    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_fagutvikling_expense'
    ) <> ARRAY['accommodation', 'days', 'employee_id', 'expense_id', 'location', 'role', 'sharing', 'ticket',
               'travel', 'type'] THEN
        RAISE EXCEPTION 'ledger_fagutvikling_expense columns do not match the expected contract';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_fagutvikling_expense'
          AND is_nullable = 'YES'
    ) THEN
        RAISE EXCEPTION 'a ledger_fagutvikling_expense column is nullable';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'ledger_fagutvikling_expense'::regclass
          AND contype = 'f'
          AND confrelid = 'employees'::regclass
    ) THEN
        RAISE EXCEPTION 'ledger_fagutvikling_expense.employee_id does not reference employees';
    END IF;
END;
$$;

ROLLBACK;
