-- Verify floq:drop_unused_functions on pg

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('fg', 'ot', 'kpi_fg', 'hours_per_project', 'time_tracking_status',
                            'upsert_expense', 'fg_bonus_employee_weekly', 'week_dates')
    ) THEN
        RAISE EXCEPTION 'an unused function is still deployed';
    END IF;
    IF to_regprocedure('public.is_weekday(date)') IS NULL THEN
        RAISE EXCEPTION 'is_weekday is gone, and apply_company_absence needs it';
    END IF;
END $$;
