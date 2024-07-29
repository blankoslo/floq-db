CREATE OR REPLACE FUNCTION public.get_weekly_staffing_dates(start_date date, end_date date)
 RETURNS TABLE(employee_id integer, first_name text, last_name text, date_of_employment date, termination_date date, year double precision, week double precision, days double precision[], project_id text, n_days bigint)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
BEGIN
	RETURN query (
		SELECT
			staffing.employee AS employee_id,
			employees.first_name,
			employees.last_name,
			employees.date_of_employment,
			employees.termination_date,
			date_part('year'::text, staffing.date) AS year,
			date_part('week'::text, staffing.date) AS week,
			array_agg(date_part('day'::text, staffing.date)) AS days,
			staffing.project AS project_id,
			count(staffing.employee) AS n_days
		FROM
			staffing
		LEFT JOIN employees ON staffing.employee = employees.id
	WHERE
		staffing.date BETWEEN DATE_TRUNC('week', start_date)
		AND(DATE_TRUNC('week', end_date) + INTERVAL '6 days')
	GROUP BY
		staffing.employee,
		employees.first_name,
		employees.last_name,
		employees.date_of_employment,
		employees.termination_date,
		date_part('year'::text, staffing.date),
		date_part('week'::text, staffing.date),
		staffing.project
	ORDER BY
		employees.first_name,
		date_part('year'::text, staffing.date),
		date_part('week'::text, staffing.date));
END
$function$
