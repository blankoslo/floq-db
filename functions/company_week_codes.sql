DROP FUNCTION IF EXISTS public.company_week_codes(date, date);

CREATE OR REPLACE FUNCTION public.company_week_codes(from_date date, to_date date)
RETURNS TABLE(
  week_start date,
  employee_id integer,
  project text,
  project_name text,
  customer text,
  customer_name text,
  billable text,
  prefix text,
  logged_hours double precision,
  staffed_hours double precision
)
LANGUAGE sql
STABLE STRICT
PARALLEL SAFE
AS $function$
WITH bounds AS (
  SELECT date_trunc('week', from_date)::date AS first_monday,
         (date_trunc('week', to_date) + interval '6 days')::date AS last_sunday
),
workday AS (
  SELECT d::date AS day, date_trunc('week', d)::date AS week_start
  FROM bounds, generate_series(first_monday, last_sunday, interval '1 day') AS d
  WHERE extract(isodow FROM d) <= 5
    AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = d::date)
),
logged AS (
  SELECT te.employee AS employee_id,
         date_trunc('week', te.date)::date AS week_start,
         te.project,
         sum(te.minutes) / 60.0 AS logged_hours
  FROM bounds, time_entry te
  WHERE te.date BETWEEN first_monday AND last_sunday
  GROUP BY te.employee, date_trunc('week', te.date), te.project
),
staffed AS (
  SELECT s.employee AS employee_id,
         wd.week_start,
         s.project,
         sum(s.percentage) * 7.5 / 100.0 AS staffed_hours
  FROM staffing s
  JOIN employees e ON e.id = s.employee
  JOIN workday wd ON wd.day = s.date
  WHERE s.date >= e.date_of_employment
    AND (e.termination_date IS NULL OR s.date <= e.termination_date)
  GROUP BY s.employee, wd.week_start, s.project
),
employee_week_project AS (
  SELECT coalesce(l.employee_id, s.employee_id) AS employee_id,
         coalesce(l.week_start, s.week_start) AS week_start,
         coalesce(l.project, s.project) AS project,
         coalesce(l.logged_hours, 0) AS logged_hours,
         coalesce(s.staffed_hours, 0) AS staffed_hours
  FROM logged l
  FULL OUTER JOIN staffed s
    ON s.employee_id = l.employee_id
   AND s.week_start = l.week_start
   AND s.project = l.project
)
SELECT ewp.week_start,
       ewp.employee_id,
       ewp.project,
       p.name AS project_name,
       p.customer,
       c.name AS customer_name,
       p.billable::text AS billable,
       left(ewp.project, 3) AS prefix,
       ewp.logged_hours::double precision AS logged_hours,
       ewp.staffed_hours::double precision AS staffed_hours
FROM employee_week_project ewp
JOIN employees e ON e.id = ewp.employee_id
JOIN projects p ON p.id = ewp.project
JOIN customers c ON c.id = p.customer
WHERE e.date_of_employment <= (ewp.week_start + interval '6 days')::date
  AND (e.termination_date IS NULL OR e.termination_date >= ewp.week_start)
  AND (ewp.logged_hours <> 0 OR ewp.staffed_hours <> 0)
ORDER BY ewp.week_start, ewp.employee_id, ewp.project;
$function$;
