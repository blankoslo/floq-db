CREATE OR REPLACE FUNCTION public.employee_worked_days_per_week(in_employee integer, in_start_of_week date DEFAULT ((('now'::text)::date + 1) - (date_part('dow'::text, ('now'::text)::date))::integer), in_number_of_weeks integer DEFAULT 8)
 RETURNS TABLE(start_of_week date, days integer, projects text[])
 LANGUAGE plpgsql
AS $function$
BEGIN
	IF(in_number_of_weeks < 1) THEN
		RAISE numeric_value_out_of_range
		USING MESSAGE = 'number_of_weeks-parameter has to be greater than 0, but was ' || in_number_of_weeks;
	END IF;
	RETURN query (
		SELECT
			current_start_of_week::date AS start_of_week,
			count(s.date)::integer AS days,
			array_agg(s.project) AS projects
		FROM
			generate_series(in_start_of_week::date, (in_start_of_week + (7 * in_number_of_weeks - 1))::date, '7 days'::interval) AS current_start_of_week
		INNER JOIN staffing s ON s.date BETWEEN current_start_of_week::date
			AND(current_start_of_week::date + 6)::date
			AND s.employee = in_employee
		WHERE NOT EXISTS (
			SELECT
				1
			FROM (
				SELECT
					employee_id,
					date,
					SUM(percentage) AS sum_percentage
				FROM
					absence
				GROUP BY
					employee_id,
					date) a
			WHERE
				a.date = s.date
				AND a.employee_id = s.employee
				AND sum_percentage >= 100
		)
		GROUP BY
			start_of_week
		ORDER BY
			start_of_week
	);
END;
$function$
