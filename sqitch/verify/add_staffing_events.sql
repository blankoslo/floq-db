-- Verify floq:add_staffing_events on pg

BEGIN;

DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'staffing_events'
          AND column_name = 'employee'
          AND data_type = 'integer'
          AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'staffing_events'
          AND column_name = 'project'
          AND data_type = 'text'
          AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'staffing_events'
          AND column_name = 'date'
          AND data_type = 'date'
          AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'staffing_events'
          AND column_name = 'percentage'
          AND data_type = 'integer'
          AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'staffing_events'
          AND column_name = 'action'
          AND data_type = 'text'
          AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'staffing_events'
          AND column_name = 'recorded_at'
          AND data_type = 'timestamp with time zone'
          AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'staffing_events columns do not have the expected contract';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'staffing_events'::regclass
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION 'staffing_events must not have foreign keys';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class
        WHERE oid = 'staffing_events'::regclass
          AND relrowsecurity
    ) THEN
        RAISE EXCEPTION 'row-level security is not enabled';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'staffing_events'
          AND policyname = 'staffing_events_write_policy'
          AND qual = 'false'
          AND with_check = 'false'
    ) THEN
        RAISE EXCEPTION 'staffing_events write policy must never be true';
    END IF;

    IF NOT has_table_privilege('employee', 'staffing_events', 'SELECT')
       OR has_table_privilege('employee', 'staffing_events', 'INSERT')
       OR has_table_privilege('employee', 'staffing_events', 'UPDATE')
       OR has_table_privilege('employee', 'staffing_events', 'DELETE') THEN
        RAISE EXCEPTION 'employee grants do not match the expected contract';
    END IF;

    IF NOT has_table_privilege('read_only', 'staffing_events', 'SELECT')
       OR has_table_privilege('read_only', 'staffing_events', 'INSERT')
       OR has_table_privilege('read_only', 'staffing_events', 'UPDATE')
       OR has_table_privilege('read_only', 'staffing_events', 'DELETE') THEN
        RAISE EXCEPTION 'read_only grants do not match the expected contract';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc
        WHERE proname = 'log_staffing_event'
          AND prosecdef
    ) THEN
        RAISE EXCEPTION 'log_staffing_event must be security definer';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'staffing'::regclass
          AND tgname = 'staffing_event'
          AND tgenabled = 'O'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'the staffing trigger is missing';
    END IF;
END;
$$;

ROLLBACK;
