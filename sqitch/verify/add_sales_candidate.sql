BEGIN;

DO
$$
BEGIN
    IF (SELECT COUNT(*) FROM sales_event_kind WHERE slug IN ('candidate_added', 'candidate_removed')) <> 2 THEN
        RAISE EXCEPTION 'the candidate event kinds are missing';
    END IF;

    IF (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'sales_candidate'
    ) <> ARRAY['case_id', 'created_at', 'created_by', 'person_id'] THEN
        RAISE EXCEPTION 'sales_candidate columns do not match the expected contract';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'sales_candidate'::regclass
          AND conname = 'sales_candidate_pkey'
          AND contype = 'p'
          AND array_length(conkey, 1) = 2
    ) THEN
        RAISE EXCEPTION 'nothing stops the same pair twice';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'sales_candidate'::regclass
          AND contype = 'f'
          AND confrelid IN ('sales_case'::regclass, 'person_card'::regclass)
          AND confdeltype = 'c'
    ) <> 2 THEN
        RAISE EXCEPTION 'a match does not follow its case and its person';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes WHERE indexname = 'sales_candidate_person_idx') THEN
        RAISE EXCEPTION 'the candidate person index is missing';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_trigger
        WHERE NOT tgisinternal
          AND tgrelid = 'sales_candidate'::regclass
          AND tgname IN ('sales_candidate_author', 'sales_candidate_added', 'sales_candidate_removed')
    ) <> 3 THEN
        RAISE EXCEPTION 'the candidate triggers are missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class
        WHERE oid = 'sales_candidate'::regclass AND relrowsecurity
    ) THEN
        RAISE EXCEPTION 'row-level security is not enabled on sales_candidate';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_policies
        WHERE tablename = 'sales_candidate'
          AND (
              (policyname = 'sales_candidate_select_policy' AND cmd = 'SELECT' AND qual = 'true')
              OR (policyname = 'sales_candidate_insert_policy' AND cmd = 'INSERT' AND with_check = 'true')
              OR (policyname = 'sales_candidate_delete_policy' AND cmd = 'DELETE' AND qual = 'true')
          )
    ) <> 3 THEN
        RAISE EXCEPTION 'the candidate policies do not match the expected contract';
    END IF;

    IF NOT has_table_privilege('employee', 'sales_candidate', 'SELECT')
       OR NOT has_table_privilege('employee', 'sales_candidate', 'INSERT')
       OR NOT has_table_privilege('employee', 'sales_candidate', 'DELETE')
       OR has_table_privilege('employee', 'sales_candidate', 'UPDATE')
       OR NOT has_table_privilege('read_only', 'sales_candidate', 'SELECT')
       OR has_table_privilege('read_only', 'sales_candidate', 'INSERT')
       OR has_table_privilege('read_only', 'sales_candidate', 'DELETE') THEN
        RAISE EXCEPTION 'candidate grants do not match the expected contract';
    END IF;
END;
$$;

ROLLBACK;
