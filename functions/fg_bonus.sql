CREATE OR REPLACE FUNCTION public.fg_bonus(from_date date, to_date date, emp_id integer DEFAULT NULL)
RETURNS TABLE(employee_id integer, bonus integer)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    e.id AS employee_id,
    COALESCE(SUM(
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
      END
    ), 0)::integer AS bonus
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
  GROUP BY e.id;
END;
$function$;
