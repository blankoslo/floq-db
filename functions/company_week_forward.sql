DROP FUNCTION IF EXISTS public.company_week_forward(date, date);

CREATE OR REPLACE FUNCTION public.company_week_forward(from_date date, to_date date)
RETURNS TABLE(
  week_start date,
  employee_id integer,
  workdays integer,
  employed_days integer,
  contract_hours double precision,
  planned_unavailable_hours double precision,
  capacity_hours double precision,
  staffed_billable_hours double precision,
  staffed_nonbillable_hours double precision,
  staffed_unavailable_hours double precision,
  staffed_fg double precision,
  last_staffed_billable_day date,
  is_fagleder boolean
)
LANGUAGE sql
STABLE STRICT
PARALLEL SAFE
AS $function$
WITH bounds AS (
  SELECT date_trunc('week', from_date)::date AS first_monday,
         (date_trunc('week', to_date) + interval '6 days')::date AS last_sunday
),
weeks AS (
  SELECT d::date AS week_start, (d + interval '6 days')::date AS week_end
  FROM bounds, generate_series(first_monday, last_sunday, interval '7 days') AS d
),
workday AS (
  SELECT d::date AS day, date_trunc('week', d)::date AS week_start
  FROM bounds, generate_series(first_monday, last_sunday, interval '1 day') AS d
  WHERE extract(isodow FROM d) <= 5
    AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = d::date)
),
week_calendar AS (
  SELECT w.week_start, w.week_end, count(wd.day)::integer AS workdays
  FROM weeks w
  LEFT JOIN workday wd ON wd.week_start = w.week_start
  GROUP BY w.week_start, w.week_end
),
employee_week AS (
  SELECT e.id AS employee_id,
         wc.week_start,
         wc.week_end,
         wc.workdays,
         count(wd.day)::integer AS employed_days
  FROM employees e
  CROSS JOIN week_calendar wc
  LEFT JOIN workday wd
         ON wd.week_start = wc.week_start
        AND wd.day >= e.date_of_employment
        AND (e.termination_date IS NULL OR wd.day <= e.termination_date)
  WHERE e.date_of_employment <= wc.week_end
    AND (e.termination_date IS NULL OR e.termination_date >= wc.week_start)
  GROUP BY e.id, wc.week_start, wc.week_end, wc.workdays
),
staffed AS (
  SELECT s.employee AS employee_id,
         date_trunc('week', s.date)::date AS week_start,
         coalesce(sum(s.percentage) FILTER (WHERE p.billable = 'billable'), 0) * 7.5 / 100.0 AS staffed_billable_hours,
         coalesce(sum(s.percentage) FILTER (WHERE p.billable = 'nonbillable'), 0) * 7.5 / 100.0 AS staffed_nonbillable_hours,
         coalesce(sum(s.percentage) FILTER (WHERE p.billable = 'unavailable'), 0) * 7.5 / 100.0 AS staffed_unavailable_hours
  FROM staffing s
  JOIN projects p ON p.id = s.project
  JOIN employees e ON e.id = s.employee
  JOIN workday wd ON wd.day = s.date
  WHERE s.date >= e.date_of_employment
    AND (e.termination_date IS NULL OR s.date <= e.termination_date)
  GROUP BY s.employee, date_trunc('week', s.date)
),
last_staffed AS (
  SELECT s.employee AS employee_id,
         max(s.date) AS last_staffed_billable_day
  FROM staffing s
  JOIN projects p ON p.id = s.project
  JOIN employees e ON e.id = s.employee
  WHERE p.billable = 'billable'
    AND extract(isodow FROM s.date) <= 5
    AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = s.date)
    AND s.date >= e.date_of_employment
    AND (e.termination_date IS NULL OR s.date <= e.termination_date)
  GROUP BY s.employee
),
planned_source AS (
  SELECT a.employee_id, a.date, a.percentage
  FROM bounds, absence a
  JOIN projects p ON p.id = a.reason
  WHERE p.billable = 'unavailable'
    AND a.date BETWEEN first_monday AND last_sunday
  UNION ALL
  SELECT s.employee, s.date, s.percentage
  FROM bounds, staffing s
  JOIN projects p ON p.id = s.project
  WHERE p.billable = 'unavailable'
    AND s.date BETWEEN first_monday AND last_sunday
),
planned_day AS (
  SELECT ps.employee_id,
         ps.date,
         least(greatest(sum(ps.percentage), 0), 100) AS percentage
  FROM planned_source ps
  JOIN employees e ON e.id = ps.employee_id
  JOIN workday wd ON wd.day = ps.date
  WHERE ps.date >= e.date_of_employment
    AND (e.termination_date IS NULL OR ps.date <= e.termination_date)
  GROUP BY ps.employee_id, ps.date
),
planned AS (
  SELECT pd.employee_id,
         date_trunc('week', pd.date)::date AS week_start,
         sum(pd.percentage) * 7.5 / 100.0 AS planned_unavailable_hours
  FROM planned_day pd
  GROUP BY pd.employee_id, date_trunc('week', pd.date)
),
capacity AS (
  SELECT ew.employee_id,
         ew.week_start,
         ew.week_end,
         ew.workdays,
         ew.employed_days,
         ew.employed_days * 7.5 AS contract_hours,
         coalesce(pl.planned_unavailable_hours, 0) AS planned_unavailable_hours,
         ew.employed_days * 7.5 - coalesce(pl.planned_unavailable_hours, 0) AS capacity_hours,
         coalesce(s.staffed_billable_hours, 0) AS staffed_billable_hours,
         coalesce(s.staffed_nonbillable_hours, 0) AS staffed_nonbillable_hours,
         coalesce(s.staffed_unavailable_hours, 0) AS staffed_unavailable_hours
  FROM employee_week ew
  LEFT JOIN staffed s ON s.employee_id = ew.employee_id AND s.week_start = ew.week_start
  LEFT JOIN planned pl ON pl.employee_id = ew.employee_id AND pl.week_start = ew.week_start
)
SELECT c.week_start,
       c.employee_id,
       c.workdays,
       c.employed_days,
       c.contract_hours::double precision AS contract_hours,
       c.planned_unavailable_hours::double precision AS planned_unavailable_hours,
       c.capacity_hours::double precision AS capacity_hours,
       c.staffed_billable_hours::double precision AS staffed_billable_hours,
       c.staffed_nonbillable_hours::double precision AS staffed_nonbillable_hours,
       c.staffed_unavailable_hours::double precision AS staffed_unavailable_hours,
       CASE WHEN c.capacity_hours > 0
            THEN (c.staffed_billable_hours / c.capacity_hours)::double precision
       END AS staffed_fg,
       ls.last_staffed_billable_day,
       EXISTS (
         SELECT 1 FROM employee_tenure_role r
         WHERE r.employee_id = c.employee_id
           AND r.tenure_role = 'Fagleder'
           AND r.from_date <= c.week_end
           AND (r.to_date IS NULL OR r.to_date >= c.week_start)
       ) AS is_fagleder
FROM capacity c
LEFT JOIN last_staffed ls ON ls.employee_id = c.employee_id
ORDER BY c.week_start, c.employee_id;
$function$;
