BEGIN;

DO
$$
DECLARE
    expected_columns CONSTANT TEXT[] := ARRAY[
        'id', 'employee_id', 'name_text', 'track_slug', 'track_since', 'note', 'created_by', 'created_at'
    ];
    missing TEXT;
BEGIN
    IF (SELECT COUNT(*) FROM person_track) <> 8
        OR (SELECT array_agg(slug) FROM person_track WHERE is_default) <> ARRAY['i_arbeid'] THEN
        RAISE EXCEPTION 'person_track is not seeded with the eight tracks and i_arbeid as the default';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = 'person_track_one_default_idx'
          AND i.indisunique
          AND i.indpred IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'nothing stops a second default track';
    END IF;

    SELECT expected
    INTO missing
    FROM unnest(expected_columns) AS expected
    WHERE expected NOT IN (
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'person_card'
    )
    LIMIT 1;

    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'person_card is missing column %', missing;
    END IF;

    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'person_card'
          AND is_nullable = 'NO'
    ) <> ARRAY['created_at', 'id', 'track_since', 'track_slug'] THEN
        RAISE EXCEPTION 'person_card nullability does not match the expected contract';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'person_card'::regclass
          AND (
              (contype = 'c' AND conname IN ('person_card_names_one_person', 'person_card_employee_id_is_stable'))
              OR (contype = 'u' AND conname = 'person_card_employee_id_key')
          )
    ) <> 3 THEN
        RAISE EXCEPTION 'person_card constraints do not match the expected contract';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'person_card_event'::regclass
          AND contype = 'f'
          AND confrelid = 'person_card'::regclass
          AND confdeltype = 'n'
    ) OR EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'person_card_event'
          AND column_name = 'card_id'
          AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'a deleted card would take its own audit trail with it';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes WHERE indexname = 'person_card_event_card_idx') THEN
        RAISE EXCEPTION 'the person event index is missing';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_trigger
        WHERE NOT tgisinternal
          AND tgname IN (
              'person_card_author',
              'person_card_track_since',
              'person_card_created',
              'person_card_track_change',
              'person_card_field_change',
              'person_card_deleted',
              'person_card_event_author'
          )
    ) <> 7 THEN
        RAISE EXCEPTION 'the person board triggers are missing';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_class
        WHERE relname IN ('person_track', 'person_card', 'person_card_event')
          AND relrowsecurity
    ) <> 3 THEN
        RAISE EXCEPTION 'row-level security is not enabled on every person board table';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename = 'person_card'
          AND policyname = 'person_card_delete_policy'
          AND cmd = 'DELETE'
          AND roles = ARRAY['employee']::name[]
          AND qual = '(employee_id IS NULL)'
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename = 'person_card'
          AND policyname = 'person_card_update_policy'
          AND cmd = 'UPDATE'
          AND qual = 'true'
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename = 'person_track'
          AND policyname = 'person_track_write_policy'
          AND cmd = 'ALL'
          AND qual = 'check_admin_write_access()'
    ) THEN
        RAISE EXCEPTION 'the person board policies do not match the expected contract';
    END IF;

    IF NOT has_table_privilege('employee', 'person_card', 'SELECT')
       OR NOT has_table_privilege('employee', 'person_card', 'INSERT')
       OR NOT has_table_privilege('employee', 'person_card', 'UPDATE')
       OR NOT has_table_privilege('employee', 'person_card', 'DELETE')
       OR NOT has_table_privilege('employee', 'person_card_event', 'INSERT')
       OR has_table_privilege('employee', 'person_card_event', 'UPDATE')
       OR has_table_privilege('employee', 'person_card_event', 'DELETE')
       OR NOT has_table_privilege('employee', 'person_track', 'UPDATE')
       OR has_table_privilege('employee', 'person_track', 'DELETE') THEN
        RAISE EXCEPTION 'employee grants do not match the expected contract';
    END IF;

    IF NOT has_table_privilege('read_only', 'person_track', 'SELECT')
       OR NOT has_table_privilege('read_only', 'person_card', 'SELECT')
       OR NOT has_table_privilege('read_only', 'person_card_event', 'SELECT')
       OR has_table_privilege('read_only', 'person_card', 'INSERT')
       OR has_table_privilege('read_only', 'person_card', 'UPDATE')
       OR has_table_privilege('read_only', 'person_card', 'DELETE') THEN
        RAISE EXCEPTION 'read_only grants do not match the expected contract';
    END IF;
END;
$$;

ROLLBACK;
