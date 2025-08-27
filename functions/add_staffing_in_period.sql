CREATE OR REPLACE FUNCTION public.add_staffing_in_period(in_employee integer, in_project text, start_date date, end_date date, in_percentage integer DEFAULT 100)
 RETURNS SETOF date
 LANGUAGE plpgsql
AS $function$
DECLARE
	is_absence boolean;
BEGIN
	SELECT EXISTS (
		SELECT 1
		FROM absence_reasons
		WHERE id = in_project
	) INTO is_absence;

	IF is_absence THEN
		RETURN QUERY (
		WITH weekdays AS (
				SELECT d::date AS cur_date
				FROM generate_series(start_date, end_date, '1 day') AS d
				WHERE is_weekday_new(d)
			),
			new_absence AS (
				INSERT INTO absence (employee_id, date, reason, percentage)
				SELECT
					in_employee AS employee_id,
					weekdays.cur_date AS date,
					in_project AS reason,
					in_percentage AS percentage
				FROM weekdays
				LEFT JOIN absence a ON a.employee_id = in_employee AND a.date = weekdays.cur_date AND a.reason = in_project
				WHERE a.employee_id IS NULL
				RETURNING date
	 		)
	 		SELECT date FROM new_absence
		);
	ELSE
		RETURN QUERY (
				WITH weekdays AS (
					SELECT d::date AS cur_date
					FROM generate_series(start_date, end_date, '1 day') AS d
					WHERE is_weekday_new(d)
				),
				new_staffing AS (
					INSERT INTO staffing (employee, date, project, percentage)
					SELECT
						in_employee AS employee,
						weekdays.cur_date AS date,
						in_project AS project,
						in_percentage AS percentage
					FROM weekdays
					LEFT JOIN staffing s ON s.employee = in_employee AND s.date = weekdays.cur_date AND s.project = in_project
					WHERE s.employee IS NULL
					RETURNING date
		 		)
		 		SELECT date FROM new_staffing
			);
	END IF;
END
$function$
