CREATE OR REPLACE FUNCTION public.get_weekly_staffing_json(start_date date, end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STRICT
AS $function$
DECLARE
    result JSONB;
BEGIN
    SELECT
        jsonb_agg(jsonb_build_object('id', e.employee_id, 'name', concat_ws(' ', e.first_name, e.last_name), 'subRows', COALESCE(s.subrows, '[]'::jsonb)) ORDER BY e.first_name, e.last_name)
    INTO result
    FROM 
        public.get_employees_in_dates(start_date, end_date) e
    LEFT JOIN (
        WITH employee_data AS (
            SELECT
                employee AS id,
                project AS name,
                TO_CHAR(DATE_TRUNC('week', date), 'IYYY-IW') AS week,
                COUNT(*) AS days_in_week
            FROM
                staffing
            WHERE
                date BETWEEN DATE_TRUNC('week', start_date::date)
                AND (DATE_TRUNC('week', end_date::date) + INTERVAL '6 days')
            GROUP BY
                employee,
                project,
                DATE_TRUNC('week', date)
        ),
        employee_projects AS (
            SELECT
                id,
                name,
                jsonb_object_agg(week, days_in_week::INT) AS week_data
            FROM
                employee_data
            GROUP BY
                id,
                name
        )
        SELECT
            id,
            jsonb_agg(jsonb_build_object('name', name) || week_data) AS subrows
        FROM
            employee_projects
        GROUP BY
            id
    ) s ON e.employee_id = s.id;

    RETURN result;
END;
$function$
