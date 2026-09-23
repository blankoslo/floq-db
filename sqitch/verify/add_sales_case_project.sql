BEGIN;

DO
$$
BEGIN
    IF (SELECT COUNT(*) FROM sales_event_kind WHERE slug IN ('project_added', 'project_removed')) <> 2 THEN
        RAISE EXCEPTION 'the project event kinds are missing';
    END IF;

    IF NOT (
        SELECT array_agg(column_name::TEXT ORDER BY column_name)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'sales_case_project'
    ) @> ARRAY['case_id', 'created_at', 'created_by', 'project_id'] THEN
        RAISE EXCEPTION 'sales_case_project columns do not match the expected contract';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'sales_case_project'::regclass
          AND conname = 'sales_case_project_pkey'
          AND contype = 'p'
          AND array_length(conkey, 1) = 2
    ) THEN
        RAISE EXCEPTION 'nothing stops the same project twice on a case';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'sales_case_project'::regclass
          AND contype = 'f'
          AND confrelid IN ('sales_case'::regclass, 'projects'::regclass)
          AND confdeltype = 'c'
    ) <> 2 THEN
        RAISE EXCEPTION 'a link does not follow its case and its project';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes WHERE indexname = 'sales_case_project_project_idx') THEN
        RAISE EXCEPTION 'the case project index is missing';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_trigger
        WHERE NOT tgisinternal
          AND tgrelid = 'sales_case_project'::regclass
          AND tgname IN ('sales_case_project_author', 'sales_case_project_added', 'sales_case_project_removed')
    ) <> 3 THEN
        RAISE EXCEPTION 'the case project triggers are missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class
        WHERE oid = 'sales_case_project'::regclass AND relrowsecurity
    ) THEN
        RAISE EXCEPTION 'row-level security is not enabled on sales_case_project';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_policies
        WHERE tablename = 'sales_case_project'
          AND (
              (policyname = 'sales_case_project_select_policy' AND cmd = 'SELECT' AND qual = 'true')
              OR (policyname = 'sales_case_project_insert_policy' AND cmd = 'INSERT' AND with_check = 'true')
              OR (policyname = 'sales_case_project_delete_policy' AND cmd = 'DELETE' AND qual = 'true')
          )
    ) <> 3 THEN
        RAISE EXCEPTION 'the case project policies do not match the expected contract';
    END IF;

    IF NOT has_table_privilege('employee', 'sales_case_project', 'SELECT')
       OR NOT has_table_privilege('employee', 'sales_case_project', 'INSERT')
       OR NOT has_table_privilege('employee', 'sales_case_project', 'DELETE')
       OR has_table_privilege('employee', 'sales_case_project', 'UPDATE')
       OR NOT has_table_privilege('read_only', 'sales_case_project', 'SELECT')
       OR has_table_privilege('read_only', 'sales_case_project', 'INSERT')
       OR has_table_privilege('read_only', 'sales_case_project', 'DELETE') THEN
        RAISE EXCEPTION 'case project grants do not match the expected contract';
    END IF;
END;
$$;

ROLLBACK;
