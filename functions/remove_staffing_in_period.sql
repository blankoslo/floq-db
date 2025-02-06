CREATE OR REPLACE FUNCTION public.remove_staffing_in_period(
    in_employee INTEGER, 
    in_project TEXT, 
    start_date DATE, 
    end_date DATE
)
RETURNS SETOF DATE
LANGUAGE plpgsql
AS $function$
DECLARE
    is_absence BOOLEAN;
BEGIN
    -- Check if the project exists in absence_reasons
    SELECT EXISTS (
        SELECT 1 FROM absence_reasons WHERE id = in_project
    ) INTO is_absence;

    RAISE NOTICE 'Function remove_staffing_in_period called for employee: %, project: %, start: %, end: %', 
        in_employee, in_project, start_date, end_date;

    IF is_absence THEN
        -- Remove from absence table if it's an absence reason
        RETURN QUERY (
            WITH weekdays AS (
                SELECT d::DATE AS cur_date
                FROM generate_series(start_date, end_date, '1 day'::interval) d
                WHERE EXTRACT(DOW FROM d) BETWEEN 1 AND 5  -- Monday to Friday
            ),
            removed_absence AS (
                DELETE FROM absence
                WHERE employee_id = in_employee 
                  AND reason = in_project 
                  AND date IN (SELECT cur_date FROM weekdays)
                RETURNING date
            )
            SELECT date FROM removed_absence
        );
    ELSE
        -- Remove from staffing table if it's not an absence reason
        RETURN QUERY (
            WITH weekdays AS (
                SELECT d::DATE AS cur_date
                FROM generate_series(start_date, end_date, '1 day'::interval) d
                WHERE EXTRACT(DOW FROM d) BETWEEN 1 AND 5  -- Monday to Friday
            ),
            removed_staffing AS (
                DELETE FROM staffing
                WHERE employee = in_employee 
                  AND project = in_project 
                  AND date IN (SELECT cur_date FROM weekdays)
                RETURNING date
            )
            SELECT date FROM removed_staffing
        );
    END IF;
END
$function$;
