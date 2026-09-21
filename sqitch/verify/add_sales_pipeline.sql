-- Verify floq:add_sales_pipeline on pg

BEGIN;

DO
$$
DECLARE
    expected_columns CONSTANT TEXT[] := ARRAY[
        'id', 'stage_slug', 'stage_since', 'customer_id', 'customer_text', 'role', 'owner_id',
        'next_step', 'deadline', 'start_week', 'end_week', 'headcount', 'framework_agreement',
        'source_text', 'trello_card_id', 'trello_url', 'attachment_count', 'extra', 'created_by',
        'created_at'
    ];
    missing TEXT;
BEGIN
    IF (SELECT COUNT(*) FROM sales_stage) <> 7
        OR (SELECT COUNT(*) FROM sales_stage WHERE is_terminal AND hides_after_months = 6) <> 3 THEN
        RAISE EXCEPTION 'sales_stage is not seeded with the seven stages';
    END IF;

    IF (SELECT COUNT(*) FROM sales_event_kind) <> 5 THEN
        RAISE EXCEPTION 'sales_event_kind is not seeded';
    END IF;

    SELECT expected
    INTO missing
    FROM unnest(expected_columns) AS expected
    WHERE expected NOT IN (
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'sales_case'
    )
    LIMIT 1;

    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'sales_case is missing column %', missing;
    END IF;

    -- Only these four are NOT NULL: Trello carries no dates, so everything else
    -- starts empty and tightening later would need a backfill.
    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'sales_case'
          AND is_nullable = 'NO'
    ) <> ARRAY['attachment_count', 'created_at', 'extra', 'framework_agreement', 'id', 'stage_since', 'stage_slug'] THEN
        RAISE EXCEPTION 'sales_case nullability does not match the expected contract';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'sales_case'::regclass
          AND conname = 'sales_case_names_someone'
          AND contype = 'c'
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'sales_case'::regclass
          AND conname = 'sales_case_trello_card_id_key'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION 'sales_case constraints do not match the expected contract';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'sales_case_event'::regclass
          AND contype = 'f'
          AND confrelid = 'sales_case'::regclass
          AND confdeltype = 'c'
    ) THEN
        RAISE EXCEPTION 'sales_case_event does not cascade from its case';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes WHERE indexname = 'sales_case_board_idx')
        OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes WHERE indexname = 'sales_case_event_case_idx') THEN
        RAISE EXCEPTION 'the board indexes are missing';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_trigger
        WHERE NOT tgisinternal
          AND tgname IN (
              'sales_case_author',
              'sales_case_stage_since',
              'sales_case_stage_change',
              'sales_case_event_author'
          )
    ) <> 4 THEN
        RAISE EXCEPTION 'the sales triggers are missing';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_class
        WHERE relname IN ('sales_stage', 'sales_event_kind', 'sales_case', 'sales_case_event')
          AND relrowsecurity
    ) <> 4 THEN
        RAISE EXCEPTION 'row-level security is not enabled on every sales table';
    END IF;

    -- The whole company reads, any employee adds, only an admin removes.
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename = 'sales_case'
          AND policyname = 'sales_case_delete_policy'
          AND cmd = 'DELETE'
          AND roles = ARRAY['employee']::name[]
          AND qual = 'check_admin_write_access()'
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename = 'sales_case'
          AND policyname = 'sales_case_insert_policy'
          AND cmd = 'INSERT'
          AND roles = ARRAY['employee']::name[]
    ) OR EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename IN ('sales_stage', 'sales_event_kind')
          AND cmd = 'ALL'
          AND qual <> 'check_admin_write_access()'
    ) THEN
        RAISE EXCEPTION 'the sales policies do not match the expected contract';
    END IF;

    IF NOT has_table_privilege('employee', 'sales_case', 'SELECT')
       OR NOT has_table_privilege('employee', 'sales_case', 'INSERT')
       OR NOT has_table_privilege('employee', 'sales_case', 'UPDATE')
       OR NOT has_table_privilege('employee', 'sales_case_event', 'INSERT')
       OR has_table_privilege('employee', 'sales_case_event', 'UPDATE')
       OR has_table_privilege('employee', 'sales_case_event', 'DELETE')
       OR NOT has_table_privilege('employee', 'sales_stage', 'UPDATE')
       OR has_table_privilege('employee', 'sales_stage', 'DELETE') THEN
        RAISE EXCEPTION 'employee grants do not match the expected contract';
    END IF;

    IF NOT has_table_privilege('read_only', 'sales_case', 'SELECT')
       OR NOT has_table_privilege('read_only', 'sales_case_event', 'SELECT')
       OR has_table_privilege('read_only', 'sales_case', 'INSERT')
       OR has_table_privilege('read_only', 'sales_case', 'UPDATE')
       OR has_table_privilege('read_only', 'sales_case', 'DELETE') THEN
        RAISE EXCEPTION 'read_only grants do not match the expected contract';
    END IF;
END;
$$;

ROLLBACK;
