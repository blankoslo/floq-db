-- Verify floq:drop_unused_tables on pg

DO $$
BEGIN
    IF to_regclass('public.talks') IS NOT NULL OR to_regclass('public.project_sdg_events') IS NOT NULL
       OR to_regclass('public.ranked_games') IS NOT NULL OR to_regclass('public.ranked_matchups') IS NOT NULL
       OR to_regtype('public.ranked_matchup_result') IS NOT NULL
       OR to_regclass('public.profession_task') IS NOT NULL OR to_regclass('public.employee_task_comments') IS NOT NULL THEN
        RAISE EXCEPTION 'an unused table is still there';
    END IF;
END $$;
