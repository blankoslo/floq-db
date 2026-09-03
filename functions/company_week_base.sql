DROP FUNCTION IF EXISTS public.company_week_base(date, date);

CREATE OR REPLACE FUNCTION public.company_week_base(from_date date, to_date date)
RETURNS TABLE(
  employee_id integer,
  week_start date,
  workdays integer,
  employed_days integer,
  contract_hours double precision,
  unavailable_hours double precision,
  available_hours double precision,
  billable_hours double precision,
  non_billable_hours double precision,
  absence_in_denominator_hours double precision,
  logged_hours double precision,
  staffed_billable_hours double precision,
  staffed_nonbillable_hours double precision,
  planned_unavailable_hours double precision,
  unregistered_days integer,
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
logged_day AS (
  SELECT DISTINCT te.employee AS employee_id, te.date AS day
  FROM bounds, time_entry te
  WHERE te.date BETWEEN first_monday AND last_sunday
),
employee_week AS (
  SELECT e.id AS employee_id,
         wc.week_start,
         wc.week_end,
         wc.workdays,
         count(wd.day)::integer AS employed_days,
         count(wd.day) FILTER (WHERE ld.day IS NULL)::integer AS unregistered_days
  FROM employees e
  CROSS JOIN week_calendar wc
  LEFT JOIN workday wd
         ON wd.week_start = wc.week_start
        AND wd.day >= e.date_of_employment
        AND (e.termination_date IS NULL OR wd.day <= e.termination_date)
  LEFT JOIN logged_day ld ON ld.employee_id = e.id AND ld.day = wd.day
  WHERE e.date_of_employment <= wc.week_end
    AND (e.termination_date IS NULL OR e.termination_date >= wc.week_start)
  GROUP BY e.id, wc.week_start, wc.week_end, wc.workdays
),
logged AS (
  SELECT te.employee AS employee_id,
         date_trunc('week', te.date)::date AS week_start,
         coalesce(sum(te.minutes) FILTER (WHERE p.billable = 'billable'), 0) / 60.0 AS billable_hours,
         coalesce(sum(te.minutes) FILTER (WHERE p.billable = 'nonbillable'), 0) / 60.0 AS non_billable_hours,
         coalesce(sum(te.minutes) FILTER (WHERE p.billable = 'unavailable'), 0) / 60.0 AS unavailable_hours,
         coalesce(sum(te.minutes) FILTER (
           WHERE p.billable = 'nonbillable' AND left(te.project, 3) IN ('PER', 'SYK')
         ), 0) / 60.0 AS absence_in_denominator_hours,
         coalesce(sum(te.minutes), 0) / 60.0 AS logged_hours
  FROM bounds, time_entry te
  JOIN projects p ON p.id = te.project
  WHERE te.date BETWEEN first_monday AND last_sunday
  GROUP BY te.employee, date_trunc('week', te.date)
),
staffed AS (
  SELECT s.employee AS employee_id,
         date_trunc('week', s.date)::date AS week_start,
         coalesce(sum(s.percentage) FILTER (WHERE p.billable = 'billable'), 0) * 7.5 / 100.0 AS staffed_billable_hours,
         coalesce(sum(s.percentage) FILTER (WHERE p.billable = 'nonbillable'), 0) * 7.5 / 100.0 AS staffed_nonbillable_hours
  FROM staffing s
  JOIN projects p ON p.id = s.project
  JOIN employees e ON e.id = s.employee
  JOIN workday wd ON wd.day = s.date
  WHERE s.date >= e.date_of_employment
    AND (e.termination_date IS NULL OR s.date <= e.termination_date)
  GROUP BY s.employee, date_trunc('week', s.date)
),
planned_day AS (
  SELECT a.employee_id,
         a.date,
         least(greatest(sum(a.percentage), 0), 100) AS percentage
  FROM absence a
  JOIN projects p ON p.id = a.reason
  JOIN employees e ON e.id = a.employee_id
  JOIN workday wd ON wd.day = a.date
  WHERE p.billable = 'unavailable'
    AND a.date >= e.date_of_employment
    AND (e.termination_date IS NULL OR a.date <= e.termination_date)
  GROUP BY a.employee_id, a.date
),
planned AS (
  SELECT pd.employee_id,
         date_trunc('week', pd.date)::date AS week_start,
         sum(pd.percentage) * 7.5 / 100.0 AS planned_unavailable_hours
  FROM planned_day pd
  GROUP BY pd.employee_id, date_trunc('week', pd.date)
)
SELECT ew.employee_id,
       ew.week_start,
       ew.workdays,
       ew.employed_days,
       (ew.employed_days * 7.5)::double precision AS contract_hours,
       coalesce(l.unavailable_hours, 0)::double precision AS unavailable_hours,
       (ew.employed_days * 7.5 - coalesce(l.unavailable_hours, 0))::double precision AS available_hours,
       coalesce(l.billable_hours, 0)::double precision AS billable_hours,
       coalesce(l.non_billable_hours, 0)::double precision AS non_billable_hours,
       coalesce(l.absence_in_denominator_hours, 0)::double precision AS absence_in_denominator_hours,
       coalesce(l.logged_hours, 0)::double precision AS logged_hours,
       coalesce(s.staffed_billable_hours, 0)::double precision AS staffed_billable_hours,
       coalesce(s.staffed_nonbillable_hours, 0)::double precision AS staffed_nonbillable_hours,
       coalesce(pl.planned_unavailable_hours, 0)::double precision AS planned_unavailable_hours,
       ew.unregistered_days,
       EXISTS (
         SELECT 1 FROM employee_tenure_role r
         WHERE r.employee_id = ew.employee_id
           AND r.tenure_role = 'Fagleder'
           AND r.from_date <= ew.week_end
           AND (r.to_date IS NULL OR r.to_date >= ew.week_start)
       ) AS is_fagleder
FROM employee_week ew
LEFT JOIN logged l ON l.employee_id = ew.employee_id AND l.week_start = ew.week_start
LEFT JOIN staffed s ON s.employee_id = ew.employee_id AND s.week_start = ew.week_start
LEFT JOIN planned pl ON pl.employee_id = ew.employee_id AND pl.week_start = ew.week_start
ORDER BY ew.week_start, ew.employee_id;
$function$;
