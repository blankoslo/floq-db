CREATE OR REPLACE FUNCTION public.weekly_fg(from_date date, to_date date, emp_id integer DEFAULT NULL)
RETURNS TABLE(employee_id integer, week_start date, available_hours double precision, billable_hours double precision)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    e.id AS employee_id,
    weeks.week_start,
    hours.available_hours,
    hours.billable_hours
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
