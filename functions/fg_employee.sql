DROP FUNCTION IF EXISTS public.fg_period(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_weekly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_weekly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_monthly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_employee_period(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_employee_weekly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_employee_weekly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_employee_monthly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_employee_monthly(integer, integer, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_employee_monthly_range(integer, integer, integer, integer, integer);

CREATE OR REPLACE FUNCTION public.fg_for_employee(emp_id integer, start_date date, end_date date)
 RETURNS TABLE(available_hours double precision, billable_hours double precision)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select
    business_hours(greatest(e.date_of_employment, start_date), least(e.termination_date, end_date)) - coalesce(sum(employee.unavailable_hours)/60.0, 0.0)::float8 as available_hours,
	  coalesce(sum(employee.billable_hours)/60.0, 0.0)::float8 as billable_hours
	from employees e
  left join (

	   select coalesce(uah.id, bh.id, nbh.id) as employee_id,
	   		uah.sum as unavailable_hours,
	        bh.sum as billable_hours,
	        nbh.sum as non_billable_hours
	    from (
        select * from unavailable_hours_for_employees(start_date,end_date)
	    ) uah
      full outer join (
	    	select * from billable_hours_for_employees(start_date,end_date)
	    ) bh on uah.id = bh.id
      full outer join (
        select * from billable_hours_for_employees(start_date,end_date)
	    ) nbh on uah.id = nbh.id

	) as employee on employee.employee_id = e.id

	where e.id = emp_id
	group by e.id
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.bonus_hours_for_employee(emp_id integer, start_date date, end_date date)
 RETURNS TABLE(available_hours double precision, bonus_billable_hours double precision)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
BEGIN
  RETURN QUERY (
    SELECT
      business_hours(greatest(e.date_of_employment, start_date), least(e.termination_date, end_date))
        - coalesce(uah.sum / 60.0, 0.0)::float8
        - coalesce(bonus_nb.sum / 60.0, 0.0)::float8 AS available_hours,
      coalesce(bh.sum / 60.0, 0.0)::float8 AS bonus_billable_hours
    FROM employees e
    LEFT JOIN (SELECT * FROM unavailable_hours_for_employees(start_date, end_date)) uah ON uah.id = e.id
    LEFT JOIN (SELECT * FROM billable_hours_for_employees(start_date, end_date)) bh ON bh.id = e.id
    LEFT JOIN (
      SELECT t.employee, sum(t.minutes)::bigint AS sum
      FROM time_entry t
      JOIN projects p ON t.project = p.id
      WHERE t.date BETWEEN start_date AND end_date
        AND p.id IN ('PER1005', 'REK1010')
      GROUP BY t.employee
    ) bonus_nb ON bonus_nb.employee = e.id
    WHERE e.id = emp_id
    GROUP BY e.id, e.date_of_employment, e.termination_date, uah.sum, bh.sum, bonus_nb.sum
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fg_employee_period(from_date date, to_date date, emp_id integer DEFAULT NULL)
RETURNS TABLE(employee_id integer, available_hours double precision, billable_hours double precision, fg_rate double precision)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    e.id AS employee_id,
    hours.available_hours,
    hours.billable_hours,
    CASE WHEN hours.available_hours > 0
         THEN hours.billable_hours / hours.available_hours
         ELSE 0.0
    END AS fg_rate
  FROM employees e
  JOIN LATERAL (
    SELECT h.available_hours, h.billable_hours
    FROM public.fg_for_employee(e.id, from_date, to_date) AS h
  ) AS hours ON true
  WHERE (emp_id IS NULL OR e.id = emp_id)
    AND e.date_of_employment <= to_date
    AND (e.termination_date IS NULL OR e.termination_date >= from_date);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fg_employee_weekly(from_date date, to_date date, emp_id integer DEFAULT NULL)
RETURNS TABLE(employee_id integer, week_start date, available_hours double precision, billable_hours double precision, fg_rate double precision)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    e.id AS employee_id,
    weeks.week_start,
    hours.available_hours,
    hours.billable_hours,
    CASE WHEN hours.available_hours > 0
         THEN hours.billable_hours / hours.available_hours
         ELSE 0.0
    END AS fg_rate
  FROM employees e
  CROSS JOIN (
    SELECT (date_trunc('week', from_date::timestamptz)::date + (n * 7))::date AS week_start
    FROM generate_series(
      0,
      ((date_trunc('week', to_date::timestamptz)::date
        - date_trunc('week', from_date::timestamptz)::date) / 7)::integer
    ) n
  ) AS weeks
  JOIN LATERAL (
    SELECT h.available_hours, h.billable_hours
    FROM public.fg_for_employee(e.id, weeks.week_start, weeks.week_start + 6) AS h
  ) AS hours ON true
  WHERE (emp_id IS NULL OR e.id = emp_id)
    AND e.date_of_employment <= to_date
    AND (e.termination_date IS NULL OR e.termination_date >= from_date);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fg_bonus_employee_weekly(from_date date, to_date date, emp_id integer DEFAULT NULL)
RETURNS TABLE(employee_id integer, week_start date, bonus_available_hours double precision, billable_hours double precision, fg_bonus_rate double precision, bonus integer)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    e.id AS employee_id,
    weeks.week_start,
    hours.available_hours AS bonus_available_hours,
    hours.bonus_billable_hours AS billable_hours,
    CASE WHEN hours.available_hours > 0
         THEN hours.bonus_billable_hours / hours.available_hours
         ELSE 0.0
    END AS fg_bonus_rate,
    CASE
      WHEN hours.available_hours <= 0 THEN 0
      WHEN EXISTS (
        SELECT 1 FROM employee_tenure_role etr
        WHERE etr.employee_id = e.id
          AND etr.tenure_role = 'Fagleder'
          AND etr.from_date <= weeks.week_start + 6
          AND (etr.to_date IS NULL OR etr.to_date >= weeks.week_start)
      ) THEN
        CASE
          WHEN hours.bonus_billable_hours / hours.available_hours >= 0.95 THEN 1000
          WHEN hours.bonus_billable_hours / hours.available_hours >= 0.90 THEN 750
          ELSE 0
        END
      ELSE
        CASE
          WHEN hours.bonus_billable_hours / hours.available_hours >= 0.95 THEN 750
          WHEN hours.bonus_billable_hours / hours.available_hours >= 0.90 THEN 500
          ELSE 0
        END
    END::integer AS bonus
  FROM employees e
  CROSS JOIN (
    SELECT (date_trunc('week', from_date::timestamptz)::date + (n * 7))::date AS week_start
    FROM generate_series(
      0,
      ((date_trunc('week', to_date::timestamptz)::date
        - date_trunc('week', from_date::timestamptz)::date) / 7)::integer
    ) n
  ) AS weeks
  JOIN LATERAL (
    SELECT h.available_hours, h.bonus_billable_hours
    FROM public.bonus_hours_for_employee(e.id, weeks.week_start, weeks.week_start + 6) AS h
  ) AS hours ON true
  WHERE (emp_id IS NULL OR e.id = emp_id)
    AND e.date_of_employment <= to_date
    AND (e.termination_date IS NULL OR e.termination_date >= from_date);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fg_bonus_employee_monthly_range(
  start_year integer, start_month integer,
  end_year integer, end_month integer,
  emp_id integer DEFAULT NULL
)
RETURNS TABLE(employee_id integer, month_start date, month_end date, bonus_available_hours double precision, billable_hours double precision, fg_bonus_rate double precision, bonus integer)
LANGUAGE plpgsql
AS $function$
DECLARE
  from_date date := make_date(start_year, start_month, 1);
  to_date   date := (make_date(end_year, end_month, 1) + interval '1 month')::date - 1;
BEGIN
  RETURN QUERY
  WITH weekly_data AS (
    SELECT
      e.id AS emp_id,
      -- Calendar month used only for grouping (majority rule: month with >=4 of the 7 days)
      CASE
        WHEN LEAST(7, (date_trunc('month', weeks.week_start::timestamptz) + interval '1 month')::date - weeks.week_start) >= 4
        THEN date_trunc('month', weeks.week_start::timestamptz)::date
        ELSE date_trunc('month', (weeks.week_start + 6)::timestamptz)::date
      END AS assigned_month,
      weeks.week_start,
      hours.available_hours,
      hours.bonus_billable_hours,
      CASE
        WHEN hours.available_hours <= 0 THEN 0
        WHEN EXISTS (
          SELECT 1 FROM employee_tenure_role etr
          WHERE etr.employee_id = e.id
            AND etr.tenure_role = 'Fagleder'
            AND etr.from_date <= weeks.week_start + 6
            AND (etr.to_date IS NULL OR etr.to_date >= weeks.week_start)
        ) THEN
          CASE
            WHEN hours.bonus_billable_hours / hours.available_hours >= 0.95 THEN 1000
            WHEN hours.bonus_billable_hours / hours.available_hours >= 0.90 THEN 750
            ELSE 0
          END
        ELSE
          CASE
            WHEN hours.bonus_billable_hours / hours.available_hours >= 0.95 THEN 750
            WHEN hours.bonus_billable_hours / hours.available_hours >= 0.90 THEN 500
            ELSE 0
          END
      END AS week_bonus
    FROM employees e
    CROSS JOIN (
      SELECT (date_trunc('week', from_date::timestamptz)::date + (n * 7))::date AS week_start
      FROM generate_series(
        0,
        ((date_trunc('week', to_date::timestamptz)::date
          - date_trunc('week', from_date::timestamptz)::date) / 7)::integer
      ) n
    ) AS weeks
    JOIN LATERAL (
      SELECT h.available_hours, h.bonus_billable_hours
      FROM public.bonus_hours_for_employee(e.id, weeks.week_start, weeks.week_start + 6) AS h
    ) AS hours ON true
    WHERE (emp_id IS NULL OR e.id = emp_id)
      AND e.date_of_employment <= to_date
      AND (e.termination_date IS NULL OR e.termination_date >= from_date)
  )
  SELECT
    wd.emp_id AS employee_id,
    min(wd.week_start) AS month_start,
    max(wd.week_start + 6) AS month_end,
    sum(wd.available_hours)::double precision AS bonus_available_hours,
    sum(wd.bonus_billable_hours)::double precision AS billable_hours,
    CASE WHEN sum(wd.available_hours) > 0
         THEN sum(wd.bonus_billable_hours) / sum(wd.available_hours)
         ELSE 0.0
    END AS fg_bonus_rate,
    sum(wd.week_bonus)::integer AS bonus
  FROM weekly_data wd
  WHERE wd.assigned_month >= make_date(start_year, start_month, 1)
    AND wd.assigned_month <= make_date(end_year, end_month, 1)
  GROUP BY wd.emp_id, wd.assigned_month
  ORDER BY wd.emp_id, wd.assigned_month;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fg_bonus_employee_monthly(year integer, month integer, emp_id integer DEFAULT NULL)
RETURNS TABLE(employee_id integer, month_start date, month_end date, bonus_available_hours double precision, billable_hours double precision, fg_bonus_rate double precision, bonus integer)
LANGUAGE sql
AS $function$
  SELECT * FROM public.fg_bonus_employee_monthly_range(year, month, year, month, emp_id);
$function$;
