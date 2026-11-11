-- Verify floq:add_ledger_fagutvikling_events on pg

BEGIN;

DO
$$
BEGIN
    IF enum_range(NULL::ledger_fagutvikling_cost)::TEXT[] IS DISTINCT FROM ARRAY['ticket', 'travel', 'accommodation'] THEN
        RAISE EXCEPTION 'ledger_fagutvikling_cost should be ticket, travel and accommodation';
    END IF;

    IF (
        SELECT array_agg(table_name::TEXT || '.' || column_name::TEXT || ':' || udt_name::TEXT
                         ORDER BY table_name, column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name IN ('ledger_fagutvikling_event', 'ledger_fagutvikling_event_attendee',
                             'ledger_fagutvikling_event_expense', 'ledger_fagutvikling_event_expense_share')
    ) IS DISTINCT FROM ARRAY[
        'ledger_fagutvikling_event.closed_at:timestamptz',
        'ledger_fagutvikling_event.comment:text',
        'ledger_fagutvikling_event.created_at:timestamptz',
        'ledger_fagutvikling_event.created_by:int4',
        'ledger_fagutvikling_event.date:date',
        'ledger_fagutvikling_event.id:text',
        'ledger_fagutvikling_event.location:text',
        'ledger_fagutvikling_event.slack_ts:text',
        'ledger_fagutvikling_event.title:text',
        'ledger_fagutvikling_event_attendee.created_at:timestamptz',
        'ledger_fagutvikling_event_attendee.days:numeric',
        'ledger_fagutvikling_event_attendee.employee_id:int4',
        'ledger_fagutvikling_event_attendee.event_id:text',
        'ledger_fagutvikling_event_attendee.role:text',
        'ledger_fagutvikling_event_attendee.sharing:text',
        'ledger_fagutvikling_event_expense.added_by:int4',
        'ledger_fagutvikling_event_expense.amount:numeric',
        'ledger_fagutvikling_event_expense.cost:ledger_fagutvikling_cost',
        'ledger_fagutvikling_event_expense.created_at:timestamptz',
        'ledger_fagutvikling_event_expense.event_id:text',
        'ledger_fagutvikling_event_expense.id:text',
        'ledger_fagutvikling_event_expense.title:text',
        'ledger_fagutvikling_event_expense.tripletex_expense_id:int8',
        'ledger_fagutvikling_event_expense_share.employee_id:int4',
        'ledger_fagutvikling_event_expense_share.expense_id:text'
    ] THEN
        RAISE EXCEPTION 'the fag arrangement tables'' columns do not match the expected contract';
    END IF;

    IF (
        SELECT array_agg(table_name::TEXT || '.' || column_name::TEXT ORDER BY table_name, column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name IN ('ledger_fagutvikling_event', 'ledger_fagutvikling_event_attendee',
                             'ledger_fagutvikling_event_expense', 'ledger_fagutvikling_event_expense_share')
          AND is_nullable = 'YES'
    ) IS DISTINCT FROM ARRAY['ledger_fagutvikling_event.closed_at', 'ledger_fagutvikling_event.comment',
                             'ledger_fagutvikling_event.slack_ts'] THEN
        RAISE EXCEPTION 'only an arrangement''s closed_at, comment and slack_ts may be null';
    END IF;

    IF (
        SELECT array_agg(conname::TEXT || ':' || contype::TEXT ORDER BY conname)
        FROM pg_catalog.pg_constraint
        WHERE conrelid IN ('ledger_fagutvikling_event'::regclass, 'ledger_fagutvikling_event_attendee'::regclass,
                           'ledger_fagutvikling_event_expense'::regclass,
                           'ledger_fagutvikling_event_expense_share'::regclass)
          AND contype IN ('c', 'f', 'p', 'u')
    ) IS DISTINCT FROM ARRAY[
        'ledger_fagutvikling_event_attendee_days_positive:c',
        'ledger_fagutvikling_event_attendee_employee_id_fkey:f',
        'ledger_fagutvikling_event_attendee_event_id_fkey:f',
        'ledger_fagutvikling_event_attendee_pkey:p',
        'ledger_fagutvikling_event_created_by_fkey:f',
        'ledger_fagutvikling_event_expense_added_by_fkey:f',
        'ledger_fagutvikling_event_expense_amount_positive:c',
        'ledger_fagutvikling_event_expense_event_id_fkey:f',
        'ledger_fagutvikling_event_expense_pkey:p',
        'ledger_fagutvikling_event_expense_share_employee_id_fkey:f',
        'ledger_fagutvikling_event_expense_share_expense_id_fkey:f',
        'ledger_fagutvikling_event_expense_share_pkey:p',
        'ledger_fagutvikling_event_expense_tripletex_expense_id_key:u',
        'ledger_fagutvikling_event_location_norge_or_utland:c',
        'ledger_fagutvikling_event_pkey:p'
    ] THEN
        RAISE EXCEPTION 'the fag arrangement tables'' constraints do not match the expected contract';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE contype = 'f'
          AND confdeltype = 'c'
          AND (conrelid, confrelid) IN (
              ('ledger_fagutvikling_event_attendee'::regclass, 'ledger_fagutvikling_event'::regclass),
              ('ledger_fagutvikling_event_expense'::regclass, 'ledger_fagutvikling_event'::regclass),
              ('ledger_fagutvikling_event_expense_share'::regclass, 'ledger_fagutvikling_event_expense'::regclass))
    ) <> 3 THEN
        RAISE EXCEPTION 'attendees and expenses do not follow their arrangement, or shares their expense';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(ARRAY['ledger_fagutvikling_event', 'ledger_fagutvikling_event_attendee',
                          'ledger_fagutvikling_event_expense', 'ledger_fagutvikling_event_expense_share']) AS t
        WHERE NOT has_table_privilege('employee', t, 'SELECT, INSERT, UPDATE, DELETE')
    ) THEN
        RAISE EXCEPTION 'employee cannot read and write every fag arrangement table';
    END IF;
END;
$$;

ROLLBACK;
