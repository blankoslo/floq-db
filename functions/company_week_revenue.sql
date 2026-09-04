DROP FUNCTION IF EXISTS public.company_week_revenue(date, date);

CREATE OR REPLACE FUNCTION public.company_week_revenue(from_date date, to_date date)
RETURNS TABLE(
  employee_id integer,
  week_start date,
  customer_id text,
  hours double precision,
  amount numeric,
  hours_missing_rate double precision
)
LANGUAGE sql
STABLE STRICT
PARALLEL SAFE
AS $function$
WITH bounds AS (
  SELECT date_trunc('week', from_date)::date AS first_monday,
         (date_trunc('week', to_date) + interval '6 days')::date AS last_sunday
),
day_hours AS (
  SELECT te.employee AS employee_id,
         p.customer  AS customer_id,
         te.date     AS day,
         date_trunc('week', te.date)::date AS week_start,
         sum(te.minutes) / 60.0 AS hours
  FROM bounds, time_entry te
  JOIN projects p ON p.id = te.project
  WHERE te.date BETWEEN first_monday AND last_sunday
    AND p.billable = 'billable'
  GROUP BY te.employee, p.customer, te.date
),
rate_periods AS (
  SELECT r.employee_id, r.customer_id, r.period_start, r.period_end, r.hourly_rate
  FROM bounds, employee_rate_periods(first_monday, last_sunday) r
)
SELECT dh.employee_id,
       dh.week_start,
       dh.customer_id,
       sum(dh.hours)::double precision,
       sum(dh.hours * coalesce(rp.hourly_rate, 0))::numeric,
       coalesce(sum(dh.hours) FILTER (WHERE rp.hourly_rate IS NULL), 0)::double precision
FROM day_hours dh
LEFT JOIN rate_periods rp
  ON rp.employee_id = dh.employee_id
 AND rp.customer_id = dh.customer_id
 AND dh.day BETWEEN rp.period_start AND rp.period_end
GROUP BY dh.employee_id, dh.week_start, dh.customer_id
ORDER BY dh.week_start, dh.employee_id, dh.customer_id;
$function$;
