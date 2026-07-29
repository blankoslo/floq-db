CREATE OR REPLACE FUNCTION public.get_latest_invoice_lock_events(in_project_ids text[],
                                                                  in_start_date date,
                                                                  in_end_date date)
    RETURNS TABLE(
        id text,
        project_id text,
        creator_first_name text,
        creator_last_name text,
        created_at timestamp,
        order_id integer,
        commit_date date,
        order_group_id integer
    )
AS
$function$
BEGIN
    RETURN QUERY (
        SELECT DISTINCT ON (ile.project_id)
            ile.id,
            ile.project_id,
            e.first_name,
            e.last_name,
            ile.created_at,
            ile.order_id,
            ile.commit_date,
            ile.order_group_id
        FROM invoice_lock_events ile
        JOIN employees e ON e.id = ile.creator_id
        WHERE ile.project_id = ANY(in_project_ids)
          AND ile.commit_date >= in_start_date
          AND ile.commit_date <= in_end_date
        ORDER BY ile.project_id, ile.created_at DESC
    );
END;
$function$ LANGUAGE plpgsql STABLE
