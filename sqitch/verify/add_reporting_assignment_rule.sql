BEGIN;

DO
$$
DECLARE
    rule_count INTEGER;
    threshold  INTEGER;
BEGIN
    SELECT COUNT(*), MIN(minimum_percentage)
    INTO rule_count, threshold
    FROM reporting_assignment_rule;

    IF rule_count <> 1 OR threshold NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'reporting_assignment_rule must contain one valid rule';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'reporting_assignment_rule'
          AND column_name = 'id'
          AND data_type = 'integer'
          AND column_default = '1'
          AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'reporting_assignment_rule'
          AND column_name = 'minimum_percentage'
          AND data_type = 'integer'
          AND column_default = '60'
          AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'reporting_assignment_rule'
          AND column_name = 'updated_at'
          AND data_type = 'timestamp with time zone'
          AND column_default = 'now()'
          AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'reporting_assignment_rule'
          AND column_name = 'updated_by'
          AND data_type = 'integer'
          AND column_default IS NULL
          AND is_nullable = 'YES'
    ) THEN
        RAISE EXCEPTION 'reporting_assignment_rule columns do not have the expected contract';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'reporting_assignment_rule'::regclass
          AND contype = 'f'
          AND confrelid = 'employees'::regclass
          AND confdeltype = 'n'
    ) THEN
        RAISE EXCEPTION 'updated_by foreign key does not have the expected contract';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class
        WHERE oid = 'reporting_assignment_rule'::regclass
          AND relrowsecurity
    ) THEN
        RAISE EXCEPTION 'row-level security is not enabled';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'reporting_assignment_rule'
          AND policyname IN (
              'reporting_assignment_rule_select_policy',
              'reporting_assignment_rule_write_policy'
          )
    ) <> 2 THEN
        RAISE EXCEPTION 'reporting_assignment_rule policies are missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'reporting_assignment_rule'
          AND policyname = 'reporting_assignment_rule_write_policy'
          AND cmd = 'ALL'
          AND roles = ARRAY['employee']::name[]
          AND qual = 'check_admin_write_access()'
          AND with_check = 'check_admin_write_access()'
    ) THEN
        RAISE EXCEPTION 'reporting_assignment_rule write policy does not enforce admin access';
    END IF;

    IF NOT has_table_privilege('employee', 'reporting_assignment_rule', 'SELECT')
       OR NOT has_column_privilege('employee', 'reporting_assignment_rule', 'minimum_percentage', 'UPDATE')
       OR has_column_privilege('employee', 'reporting_assignment_rule', 'id', 'UPDATE')
       OR has_column_privilege('employee', 'reporting_assignment_rule', 'updated_at', 'UPDATE')
       OR has_column_privilege('employee', 'reporting_assignment_rule', 'updated_by', 'UPDATE')
       OR has_table_privilege('employee', 'reporting_assignment_rule', 'INSERT')
       OR has_table_privilege('employee', 'reporting_assignment_rule', 'DELETE') THEN
        RAISE EXCEPTION 'employee grants do not match the expected contract';
    END IF;

    IF NOT has_table_privilege('read_only', 'reporting_assignment_rule', 'SELECT')
       OR has_table_privilege('read_only', 'reporting_assignment_rule', 'INSERT')
       OR has_table_privilege('read_only', 'reporting_assignment_rule', 'UPDATE')
       OR has_table_privilege('read_only', 'reporting_assignment_rule', 'DELETE') THEN
        RAISE EXCEPTION 'read_only grants do not match the expected contract';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'reporting_assignment_rule'::regclass
          AND tgname = 'reporting_assignment_rule_metadata'
          AND tgenabled = 'O'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'metadata trigger is missing';
    END IF;

    BEGIN
        UPDATE reporting_assignment_rule SET minimum_percentage = 0;
        RAISE EXCEPTION 'minimum_percentage accepted zero';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE reporting_assignment_rule SET minimum_percentage = 101;
        RAISE EXCEPTION 'minimum_percentage accepted a value above 100';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO reporting_assignment_rule (id) VALUES (2);
        RAISE EXCEPTION 'reporting_assignment_rule accepted a second singleton id';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;
