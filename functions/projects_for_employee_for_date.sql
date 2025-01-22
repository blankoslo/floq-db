CREATE OR REPLACE FUNCTION public.projects_for_employee_for_date(employee_id integer, date date DEFAULT ('now'::text)::date)
 RETURNS TABLE(id text, project text, customer text, minutes integer, percentage_staffed integer)
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
WITH staffed_projects AS (
    SELECT DISTINCT s.project, p.name, p.id, c.name as customer_name, s.percentage
    FROM staffing as s
    JOIN projects as p ON s.project = p.id
    JOIN customers as c ON p.customer = c.id
    WHERE date = $2 AND employee = $1
),
time_entries AS (
    SELECT e.project, sum(e.minutes) as minutes
    FROM time_entry e
    WHERE e.date = $2 AND e.employee = $1
    GROUP BY e.project
),
absence_entries AS (
    SELECT 
        ar.id as project,
        ar.name as name,
        'Internt' as customer_name,
        0::integer as minutes,
        a.percentage
    FROM absence a
    JOIN absence_reasons ar ON a.reason = ar.id
    WHERE a.employee_id = $1 AND a.date = $2
)
SELECT 
    COALESCE(sp.id, p.id, ae.project) as id,
    COALESCE(sp.name, p.name, ae.name) as name,
    COALESCE(sp.customer_name, c.name, ae.customer_name) as customer_name,
    COALESCE(te.minutes, ae.minutes, 0)::integer as minutes,
    COALESCE(sp.percentage, ae.percentage, 0) as percentage
FROM staffed_projects sp
FULL OUTER JOIN time_entries te ON te.project = sp.project
FULL OUTER JOIN projects p ON p.id = te.project
FULL OUTER JOIN absence_entries ae ON ae.project = sp.project
LEFT JOIN customers c ON p.customer = c.id
WHERE te.project IS NOT NULL 
   OR sp.project IS NOT NULL 
   OR ae.project IS NOT NULL;
$function$;
