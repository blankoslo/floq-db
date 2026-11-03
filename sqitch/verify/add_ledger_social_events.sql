-- Verify floq:add_ledger_social_events on pg

BEGIN;

DO
$$
BEGIN
    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_social_event'
    ) IS DISTINCT FROM ARRAY['category', 'closed_at', 'comment', 'created_at', 'created_by', 'date', 'id',
                             'participant_count', 'title'] THEN
        RAISE EXCEPTION 'ledger_social_event columns do not match the expected contract';
    END IF;

    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_social_event_utgift'
    ) IS DISTINCT FROM ARRAY['added_by', 'amount', 'created_at', 'event_id', 'id', 'title', 'tripletex_expense_id'] THEN
        RAISE EXCEPTION 'ledger_social_event_utgift columns do not match the expected contract';
    END IF;

    IF (
        SELECT array_agg(table_name::TEXT || '.' || column_name::TEXT ORDER BY table_name, column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name IN ('ledger_social_event', 'ledger_social_event_utgift')
          AND is_nullable = 'YES'
    ) IS DISTINCT FROM ARRAY['ledger_social_event.closed_at', 'ledger_social_event.comment',
                             'ledger_social_event_utgift.tripletex_expense_id'] THEN
        RAISE EXCEPTION 'only closed_at, comment and tripletex_expense_id may be null';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'ledger_social_event_utgift'::regclass
          AND contype = 'f'
          AND confrelid = 'ledger_social_event'::regclass
          AND confdeltype = 'c'
    ) THEN
        RAISE EXCEPTION 'utgifter do not follow their event';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'ledger_social_event_utgift'::regclass
          AND conname = 'ledger_social_event_utgift_tripletex_expense_id_key'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION 'an utlegg can be on more than one utgift';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(ARRAY['ledger_social_event', 'ledger_social_event_utgift']) AS t
        WHERE NOT has_table_privilege('employee', t, 'SELECT, INSERT, UPDATE, DELETE')
    ) THEN
        RAISE EXCEPTION 'employee cannot read and write every event table';
    END IF;
END;
$$;

ROLLBACK;
