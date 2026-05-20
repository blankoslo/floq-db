DROP FUNCTION IF EXISTS public.fg_period(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_weekly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_weekly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_monthly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_employee_weekly(date, date, integer);
DROP FUNCTION IF EXISTS public.fg_bonus_employee_monthly(date, date, integer);

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
          AND etr.tenure_role = 'fagansvarlig'
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

CREATE OR REPLACE FUNCTION public.fg_bonus_employee_monthly(from_date date, to_date date, emp_id integer DEFAULT NULL)
RETURNS TABLE(employee_id integer, month_start date, bonus_available_hours double precision, billable_hours double precision, fg_bonus_rate double precision, bonus integer)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  WITH weekly_data AS (
    SELECT
      e.id AS emp_id,
      -- Assign each week to the month containing the majority (>=4) of its days
      CASE
        WHEN LEAST(7, (date_trunc('month', weeks.week_start::timestamptz) + interval '1 month')::date - weeks.week_start) >= 4
        THEN date_trunc('month', weeks.week_start::timestamptz)::date
        ELSE date_trunc('month', (weeks.week_start + 6)::timestamptz)::date
      END AS month_start,
      hours.available_hours,
      hours.bonus_billable_hours,
      CASE
        WHEN hours.available_hours <= 0 THEN 0
        WHEN EXISTS (
          SELECT 1 FROM employee_tenure_role etr
          WHERE etr.employee_id = e.id
            AND etr.tenure_role = 'fagansvarlig'
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
    wd.month_start,
    sum(wd.available_hours)::double precision AS bonus_available_hours,
    sum(wd.bonus_billable_hours)::double precision AS billable_hours,
    CASE WHEN sum(wd.available_hours) > 0
         THEN sum(wd.bonus_billable_hours) / sum(wd.available_hours)
         ELSE 0.0
    END AS fg_bonus_rate,
    sum(wd.week_bonus)::integer AS bonus
  FROM weekly_data wd
  GROUP BY wd.emp_id, wd.month_start
  ORDER BY wd.emp_id, wd.month_start;
END;
$function$;
