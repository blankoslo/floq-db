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

        -- Which person-days are gone.
        --
        -- One row in `absence` means that whole day is away, which is the
        -- convention get_weekly_staffing_json and apply_weekly_staffing already
        -- use: the first reports every absence row as 100%, the second counts
        -- one row per date as one whole day. DISTINCT because the table is keyed
        -- by (employee_id, reason, date), so a fagdag booked inside somebody's
        -- ferie puts two rows on one Tuesday — and that is one day gone, not two.
        WITH away AS (
            SELECT DISTINCT a.employee_id AS employee, a.date AS date
            FROM absence a
            WHERE a.date BETWEEN cur_week_start AND (cur_week_start + INTERVAL '6 days')::date
        ),
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
        -- `staffing` holds what was PLANNED. Absence sits on top of it and is
        -- never subtracted from it — see weekly_staffing_write.sql. Reading the
        -- rows raw therefore counted days that are not going to happen: a full
        -- billable week plus two days of ferie kept all five days up here, while
        -- the same ferie took two days OUT of the available hours below. So FG
        -- went up when somebody took time off, and 100% read as 167%.
        --
        -- On a day that is away, the plan for it is dropped. Where the day is
        -- only partly planned the drop is proportional, so a day holding 60%
        -- billable and 40% internal loses 60/40 of whatever the absence covers:
        -- absence is a fact about the day, with no reason to prefer either half.
        --
        -- On a day nobody is away this reduces to pct * billable_pct / pct, which
        -- is billable_pct — exactly what the old query summed. Weeks with no
        -- absence in them therefore report the same FG as before.
        --
        -- ::numeric is load-bearing. `percentage` is an integer, so SUM() is
        -- bigint and billable_pct / pct would be integer division: an overbooked
        -- day of 130% would truncate its billable share instead of scaling it.
        billable_hours AS (
            SELECT COALESCE(SUM(
                       CASE WHEN pl.pct > 0
                            THEN GREATEST(pl.pct - CASE WHEN aw.date IS NULL THEN 0 ELSE 100 END, 0)
                                 * pl.billable_pct::numeric / pl.pct
                            ELSE 0
                       END
                   ) * 7.5 / 100.0, 0) AS hours
            FROM planned pl
            LEFT JOIN away aw ON aw.employee = pl.employee AND aw.date = pl.date
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
        -- Only absence marked 'unavailable' comes out here, while billable_hours
        -- above drops EVERY kind. That difference is deliberate, and it is why a
        -- fagdag lowers FG and a day of ferie does not:
        --
        --   Anna, 5 billable days booked, one fagdag on the Tuesday
        --     billable hours   4 days   Tuesday dropped above
        --     available hours  5 days   FAG1000 is not 'unavailable'
        --     FG               80%
        --
        --   Anna, 5 billable days booked, one day of ferie instead
        --     billable hours   4 days   dropped above
        --     available hours  4 days   FER1000 IS 'unavailable'
        --     FG               100%
        --
        -- Both are right. Ferie was never Blank's to sell, so it leaves the sum
        -- altogether. A fagdag is a day Blank had and chose to spend on itself,
        -- so it stays in what was available and costs FG. Which side a reason
        -- falls on is decided by absence_reasons.billable and nowhere here.
        --
        -- COUNT(DISTINCT (employee, date)), for the same reason as `away`: two
        -- unavailable reasons on one person's Tuesday took 15 hours out of the
        -- week instead of 7.5, which pushed FG up a second way.
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
-- STABLE because this only reads; the apps call it over GET.
$$ LANGUAGE plpgsql STABLE;
