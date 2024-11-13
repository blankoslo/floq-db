CREATE OR REPLACE FUNCTION public.remove_staffing_in_period(in_employee integer, in_project text, start_date date, end_date date)
 RETURNS SETOF date
 LANGUAGE plpgsql
AS $function$
BEGIN
	RETURN QUERY (
		WITH RECURSIVE date_range AS (
			SELECT start_date::date AS cur_date
			UNION ALL
			SELECT cur_date + 1
			FROM date_range
			WHERE cur_date < end_date::date
		),
		weekdays AS (
			SELECT cur_date
			FROM date_range
			WHERE EXTRACT(DOW FROM cur_date) BETWEEN 1 AND 5
		),
		removed_absence AS (
			DELETE FROM absence
			WHERE EXISTS (
				SELECT 1
				FROM absence_reasons
                WHERE id = in_project
            )
            AND employee_id = in_employee
            AND reason = in_project
            AND date IN (SELECT cur_date FROM weekdays)
			RETURNING date
		),
		removed_staffing AS (
			DELETE FROM staffing
			WHERE NOT EXISTS (
				SELECT 1
				FROM absence_reasons
                WHERE id = in_project
            )
            AND employee = in_employee
            AND project = in_project
            AND date IN (SELECT cur_date FROM weekdays)
			RETURNING date
        )
 		SELECT date FROM removed_absence
        UNION ALL
 		SELECT date FROM removed_staffing
	);
END
$function$
