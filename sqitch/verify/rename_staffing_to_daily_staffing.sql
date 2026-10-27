-- Verify floq:rename_staffing_to_daily_staffing on pg

DO $$
BEGIN
    IF to_regclass('public.staffing') IS NOT NULL OR to_regclass('public.daily_staffing') IS NULL THEN
        RAISE EXCEPTION 'staffing has not been renamed to daily_staffing';
    END IF;
    IF has_table_privilege('employee', 'public.daily_staffing', 'INSERT') THEN
        RAISE EXCEPTION 'daily_staffing is still writable by employee';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('apply_weekly_staffing', 'restore_weekly_staffing', 'get_weekly_staffing_json',
                            'planned_billable_hours', 'forcasted_available_hours', 'company_week_base')
    ) THEN
        RAISE EXCEPTION 'a function on staffing is still deployed';
    END IF;
END $$;
