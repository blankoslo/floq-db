CREATE OR REPLACE FUNCTION public.weekly_forecasted_fg_json(start_date date, end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
	cur_week_start date;
	period_end date;
	result jsonb := '{}'::jsonb;
	str_week text;
	ffg_value double precision;
BEGIN
	cur_week_start := DATE_TRUNC('week', start_date);
	period_end := DATE_TRUNC('week', end_date);
	WHILE cur_week_start <= period_end LOOP
		str_week := TO_CHAR(cur_week_start, 'IYYY-IW');
		SELECT
			ffg.percent INTO ffg_value
		FROM
			forcasted_fg_in_period (cur_week_start,
				(cur_week_start + INTERVAL '6 days')::date) ffg;
		result := result || jsonb_build_object (str_week,
			TRUNC(ffg_value));
		cur_week_start := cur_week_start::date + INTERVAL '7 days';
	END LOOP;
	RETURN result;
END
$function$;

CREATE OR REPLACE FUNCTION public.weekly_fg_json(start_date date, end_date date)
  RETURNS jsonb
AS
$$
DECLARE
    cur_week_start date;
    period_end date;
    result jsonb := '{}'::jsonb;
    str_week text;
    total_billable_hours double precision;
    total_available_hours double precision;
    billable_percentage double precision;
BEGIN
    cur_week_start := DATE_TRUNC('week', start_date);
    period_end := DATE_TRUNC('week', end_date);

    WHILE cur_week_start <= period_end LOOP
        str_week := TO_CHAR(cur_week_start, 'IYYY-IW');

        WITH billable_hours AS (
            SELECT COALESCE(SUM(s.percentage * 7.5) / 100.0, 0) AS hours
            FROM staffing s
            INNER JOIN projects p ON s.project = p.id
            WHERE p.billable = 'billable'
            AND s.date BETWEEN cur_week_start AND (cur_week_start + INTERVAL '6 days')::date
        ),
        employee_count AS (
            SELECT COUNT(employee_id) AS count
            FROM get_employees_in_dates(cur_week_start, (cur_week_start + INTERVAL '6 days')::date)
        ),
        working_day_count AS (
            SELECT COUNT(*) AS count
            FROM available_dates_new(cur_week_start, (cur_week_start + INTERVAL '6 days')::date)
        ),
        potential_hours AS (
            SELECT ec.count * wdc.count * 7.5 AS hours
            FROM employee_count ec
            CROSS JOIN working_day_count wdc
        ),
        unavailable_hours AS (
            SELECT COALESCE(COUNT(a.date) * 7.5, 0) AS hours
            FROM absence a
            INNER JOIN absence_reasons ar ON a.reason = ar.id
            WHERE ar.billable = 'unavailable'
            AND a.date BETWEEN cur_week_start AND (cur_week_start + INTERVAL '6 days')::date
        ),
        calculations AS (
            SELECT
                bh.hours AS billable_hours,
                (ph.hours - uh.hours) AS available_hours
            FROM billable_hours bh
            CROSS JOIN potential_hours ph
            CROSS JOIN unavailable_hours uh
        )
        SELECT
            c.billable_hours,
            c.available_hours
        INTO total_billable_hours, total_available_hours
        FROM calculations c;

        -- Calculate billable percentage (FG)
        IF total_available_hours > 0 THEN
            billable_percentage := (total_billable_hours / total_available_hours) * 100;
        ELSE
            billable_percentage := 0;
        END IF;

        result := result || jsonb_build_object(str_week, ROUND(billable_percentage::numeric, 1));

        cur_week_start := cur_week_start + INTERVAL '7 days';
    END LOOP;

    RETURN result;
END
$$ LANGUAGE plpgsql;
