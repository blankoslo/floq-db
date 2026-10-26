CREATE OR REPLACE FUNCTION public.unavailable_hours_for_employees(start_date date, end_date date)
 RETURNS TABLE(id integer, sum bigint)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select t.employee, sum(minutes)
    from time_entry t, projects p
    where t.project = p.id
    and t.date between start_date and end_date
    and p.billable = 'unavailable'
    group by t.employee
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.billable_hours_for_employees(start_date date, end_date date)
 RETURNS TABLE(id integer, sum bigint)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select t.employee, sum(minutes)
    from time_entry t, projects p
    where t.project = p.id
    and t.date between start_date and end_date
    and p.billable = 'billable'
    group by t.employee
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.nonbillable_hours_for_employees(start_date date, end_date date)
 RETURNS TABLE(id integer, sum bigint)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select t.employee, sum(minutes)
    from time_entry t, projects p
    where t.project = p.id
    and t.date between start_date and end_date
    and p.billable = 'nonbillable'
    group by t.employee
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.time_tracking_status(start_date date, end_date date)
 RETURNS TABLE(name text,
    email text,
    available_hours double precision,
    billable_hours double precision,
    non_billable_hours double precision,
    unavailable_hours double precision,
    unregistered_days integer,
    last_date date,
    last_created date
 )
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select e.first_name || ' ' || e.last_name as name,
       e.email,
       business_hours(greatest(e.date_of_employment, start_date), least(e.termination_date, end_date)) - coalesce(sum(t.unavailable_hours)/60.0, 0.0)::float8 as available_hours,
       coalesce(sum(t.billable_hours)/60.0, 0.0)::float8 as billable_hours,
       coalesce(sum(t.non_billable_hours)/60.0, 0.0)::float8 as non_billable_hours,
       coalesce(sum(t.unavailable_hours)/60.0, 0.0)::float8 as unavailable_hours,
       (select * from unregistered_days(start_date,end_date,e.id) u) as unregistered_days,
       ld.date,
       lc.created::date
    from employees e
    left join (
        select coalesce(uah.id, bh.id, nbh.id) as employee_id,
            uah.sum as unavailable_hours,
            bh.sum as billable_hours,
            nbh.sum as non_billable_hours
        from (
          select * from unavailable_hours_for_employees(start_date,end_date)
        ) uah
        full outer join (
          select * from billable_hours_for_employees(start_date,end_date)
        ) bh on uah.id = bh.id
        full outer join (
          select * from nonbillable_hours_for_employees(start_date,end_date)
        ) nbh on uah.id = nbh.id
    ) as t on t.employee_id = e.id

    -- find last time_entry date for employees
    left join (
      select distinct on(te.employee) te.employee, te.date
          from time_entry te
          order by te.employee, te.date desc
    ) ld on ld.employee=e.id

    -- find last time_entry created for employees
    left join (
      select distinct on(te.employee) te.employee, te.created
          from time_entry te
          order by te.employee, te.created desc
    ) lc on lc.employee=e.id

    where e.date_of_employment <= end_date
    and (e.termination_date is null or e.termination_date >= start_date)
    group by e.id, ld.date, lc.created
    order by e.first_name, e.last_name
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.unavailable_absence_days_for_employees(start_date date, end_date date)
 RETURNS TABLE(id integer, days bigint)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select a.employee_id, count(a)
    from absence a, projects p
    where a.reason = p.id
    and a.date between start_date and end_date
    and p.billable = 'unavailable'
    group by a.employee_id
  );
end
$function$;

DROP FUNCTION IF EXISTS public.employee_yearly_bonus(integer, integer);
DROP FUNCTION IF EXISTS public.employee_weekly_fg(integer, integer);

CREATE OR REPLACE FUNCTION public.employee_has_sick_child_days(emp_id integer)
RETURNS boolean
LANGUAGE sql
STABLE STRICT
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM time_entry WHERE employee = emp_id AND project = 'SYK1002' LIMIT 1
  );
$function$;
