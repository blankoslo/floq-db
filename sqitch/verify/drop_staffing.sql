-- Verify floq:drop_staffing on pg

DO $$
BEGIN
    IF to_regclass('public.staffing') IS NOT NULL THEN
        RAISE EXCEPTION 'staffing still exists';
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
