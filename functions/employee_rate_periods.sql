DROP FUNCTION IF EXISTS public.employee_rate_periods(date, date, text);

CREATE OR REPLACE FUNCTION public.employee_rate_periods(
  in_from_date date,
  in_to_date date,
  in_customer_id text DEFAULT NULL
)
RETURNS TABLE(
  employee_id integer,
  customer_id text,
  period_start date,
  period_end date,
  hourly_rate numeric
)
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $function$
WITH applicable AS (
  SELECT DISTINCT ON (pm.employee_id, pm.customer_id, pm.from_date)
         pm.employee_id,
         pm.customer_id,
         pm.from_date,
         pm.hourly_rate
  FROM project_members pm
  WHERE pm.from_date <= in_to_date
    AND (in_customer_id IS NULL OR pm.customer_id = in_customer_id)
  ORDER BY pm.employee_id, pm.customer_id, pm.from_date, pm.id
),
bounded AS (
  SELECT a.employee_id,
         a.customer_id,
         greatest(a.from_date, in_from_date) AS period_start,
         least(
           coalesce(
             lead(a.from_date) OVER (
               PARTITION BY a.employee_id, a.customer_id ORDER BY a.from_date
             ) - 1,
             in_to_date
           ),
           in_to_date
         ) AS period_end,
         a.hourly_rate
  FROM applicable a
)
SELECT b.employee_id, b.customer_id, b.period_start, b.period_end, b.hourly_rate
FROM bounded b
WHERE b.period_start <= b.period_end
ORDER BY b.employee_id, b.customer_id, b.period_start;
$function$;
