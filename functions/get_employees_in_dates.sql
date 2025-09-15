CREATE OR REPLACE FUNCTION public.get_employees_in_dates(start_date date, end_date date)
 RETURNS TABLE(employee_id integer, first_name text, last_name text, role text, image_url text)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
BEGIN
	RETURN query (
		SELECT
			employees.id,
			employees.first_name,
			employees.last_name,
			employees.role,
			employees.image_url
		FROM
			employees
		WHERE
			employees.date_of_employment <= end_date
			AND(employees.termination_date IS NULL
				OR employees.termination_date >= start_date)
		ORDER BY
			employees.first_name);
END
$function$
