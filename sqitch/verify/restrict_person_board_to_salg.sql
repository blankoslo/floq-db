BEGIN;

SELECT has_salg_access();

DO
$$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename IN ('person_track', 'person_card', 'person_card_event', 'sales_candidate')
          AND cmd = 'SELECT'
          AND qual NOT LIKE '%has_salg_access()%'
    ) THEN
        RAISE EXCEPTION 'a person board table is still readable without the salg role';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_policies
        WHERE tablename IN ('person_card', 'sales_candidate')
          AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
          AND coalesce(qual, '') || coalesce(with_check, '') LIKE '%has_salg_access()%'
    ) <> 6 THEN
        RAISE EXCEPTION 'a write policy on person_card or sales_candidate does not require the salg role';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE tablename = 'sales_case_event'
          AND policyname = 'sales_case_event_select_policy'
          AND qual LIKE '%candidate_added%'
          AND qual LIKE '%has_salg_access()%'
    ) THEN
        RAISE EXCEPTION 'candidate events on a sales case are readable without the salg role';
    END IF;

    IF NOT (SELECT prosecdef FROM pg_catalog.pg_proc WHERE proname = 'log_sales_candidate_change') THEN
        RAISE EXCEPTION 'log_sales_candidate_change cannot see the person board for someone without the salg role';
    END IF;
END;
$$;

ROLLBACK;
