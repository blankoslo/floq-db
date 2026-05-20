CREATE OR REPLACE FUNCTION public.fg(from_date date, to_date date, emp_id integer DEFAULT NULL)
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
