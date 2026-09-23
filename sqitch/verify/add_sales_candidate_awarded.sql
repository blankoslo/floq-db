BEGIN;

SELECT awarded, awarded_at FROM sales_candidate WHERE FALSE;

DO
$$
BEGIN
    IF (SELECT COUNT(*) FROM sales_event_kind WHERE slug IN ('candidate_awarded', 'candidate_unawarded')) <> 2 THEN
        RAISE EXCEPTION 'the award event kinds are missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'sales_candidate'
          AND column_name = 'awarded'
          AND is_nullable = 'NO'
          AND column_default = 'false'
    ) THEN
        RAISE EXCEPTION 'sales_candidate.awarded is not a non-null flag that starts false';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_trigger
        WHERE NOT tgisinternal
          AND tgrelid = 'sales_candidate'::regclass
          AND tgname IN ('sales_candidate_awarded_at', 'sales_candidate_award_change')
    ) <> 2 THEN
        RAISE EXCEPTION 'the award triggers are missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename = 'sales_candidate'
          AND policyname = 'sales_candidate_update_policy'
          AND cmd = 'UPDATE'
          AND qual IN ('true', 'has_salg_access()')
          AND with_check IN ('true', 'has_salg_access()')
    ) THEN
        RAISE EXCEPTION 'the candidate update policy does not match the expected contract';
    END IF;

    IF NOT has_column_privilege('employee', 'sales_candidate', 'awarded', 'UPDATE')
       OR has_column_privilege('employee', 'sales_candidate', 'awarded_at', 'UPDATE')
       OR has_column_privilege('employee', 'sales_candidate', 'case_id', 'UPDATE')
       OR has_column_privilege('employee', 'sales_candidate', 'person_id', 'UPDATE')
       OR has_column_privilege('read_only', 'sales_candidate', 'awarded', 'UPDATE') THEN
        RAISE EXCEPTION 'only the award flag may be updated, and only by employee';
    END IF;
END;
$$;

ROLLBACK;
