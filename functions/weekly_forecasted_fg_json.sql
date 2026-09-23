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

        -- One absence row = the whole day away. DISTINCT: several reasons can
        -- share a day.
        WITH away AS (
            SELECT DISTINCT a.employee_id AS employee, a.date AS date
            FROM absence a
            WHERE a.date BETWEEN cur_week_start AND (cur_week_start + INTERVAL '6 days')::date
        ),
        -- Includes rows on public holidays; the cap in billable_hours handles them.
        planned AS (
            SELECT s.employee,
                   s.date,
                   SUM(s.percentage) AS pct,
                   SUM(CASE WHEN p.billable = 'billable' THEN s.percentage ELSE 0 END)
                       AS billable_pct
            FROM staffing s
            LEFT JOIN projects p ON s.project = p.id
            WHERE s.date BETWEEN cur_week_start AND (cur_week_start + INTERVAL '6 days')::date
            GROUP BY s.employee, s.date
        ),
        away_count AS (
            SELECT aw.employee, COUNT(*)::numeric AS days
            FROM away aw
            GROUP BY aw.employee
        ),
        working_day_count AS (
            SELECT COUNT(*) AS count
            FROM available_dates_new(cur_week_start, (cur_week_start + INTERVAL '6 days')::date)
        ),
        -- Absence is not subtracted from `staffing`, so a day's plan is reduced
        -- here, split proportionally between billable and non-billable.
        -- ::numeric avoids integer division.
        per_employee AS (
            SELECT pl.employee,
                   SUM(CASE WHEN pl.pct > 0
                            THEN GREATEST(pl.pct - CASE WHEN aw.date IS NULL THEN 0 ELSE 100 END, 0)
                            ELSE 0 END) / 100.0 AS days,
                   SUM(CASE WHEN pl.pct > 0
                            THEN GREATEST(pl.pct - CASE WHEN aw.date IS NULL THEN 0 ELSE 100 END, 0)
                                 * pl.billable_pct::numeric / pl.pct
                            ELSE 0 END) / 100.0 AS billable_days
            FROM planned pl
            LEFT JOIN away aw ON aw.employee = pl.employee AND aw.date = pl.date
            GROUP BY pl.employee
        ),
        -- Cap each person's planned days at their working days minus absence,
        -- keeping the billable share. Must be per person, before summing.
        billable_hours AS (
            SELECT COALESCE(SUM(
                       CASE WHEN pe.days > 0
                            THEN LEAST(pe.days,
                                       GREATEST(wdc.count - COALESCE(ac.days, 0), 0))
                                 * pe.billable_days / pe.days
                            ELSE 0
                       END
                   ) * 7.5, 0) AS hours
            FROM per_employee pe
            CROSS JOIN working_day_count wdc
            LEFT JOIN away_count ac ON ac.employee = pe.employee
        ),
        employee_count AS (
            SELECT COUNT(employee_id) AS count
            FROM get_employees_in_dates(cur_week_start, (cur_week_start + INTERVAL '6 days')::date)
        ),
        potential_hours AS (
            SELECT ec.count * wdc.count * 7.5 AS hours
            FROM employee_count ec
            CROSS JOIN working_day_count wdc
        ),
        -- Only 'unavailable' absence reduces available hours, while billable_hours
        -- drops every kind: so a fagdag lowers FG and ferie does not.
        unavailable_hours AS (
            SELECT COALESCE(COUNT(DISTINCT (a.employee_id, a.date)) * 7.5, 0) AS hours
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
$$ LANGUAGE plpgsql STABLE;
