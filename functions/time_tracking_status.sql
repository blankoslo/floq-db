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
 RETURNS TABLE(name text, email text, available_hours double precision, billable_hours double precision, non_billable_hours double precision, unavailable_hours double precision, unregistered_days integer, last_date date, last_created date)
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

CREATE OR REPLACE FUNCTION public.staffed_billable_days_for_employees(start_date date, end_date date)
 RETURNS TABLE(id integer, days bigint)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select s.employee, count(s)
    from staffing s, projects p
    where s.project = p.id
    and s.date between start_date and end_date
    and p.billable = 'billable'
    group by s.employee
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.staffed_nonbillable_days_for_employees(start_date date, end_date date)
 RETURNS TABLE(id integer, days bigint)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select s.employee, count(s)
    from staffing s, projects p
    where s.project = p.id
    and s.date between start_date and end_date
    and p.billable = 'nonbillable'
    group by s.employee
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.staffed_unavailable_days_for_employees(start_date date, end_date date)
 RETURNS TABLE(id integer, days bigint)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select s.employee, count(s)
    from staffing s, projects p
    where s.project = p.id
    and s.date between start_date and end_date
    and p.billable = 'unavailable'
    group by s.employee
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.time_tracking_status_with_staffing(start_date date, end_date date)
RETURNS TABLE(
    name text,
    email text,
    available_hours double precision,
    staffed_billable_hours double precision,
    billable_hours double precision,
    staffed_nonbillable_hours double precision,
    non_billable_hours double precision,
    staffed_unavailable_hours double precision,
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
       coalesce(sum(t.staffed_billable_days) * 7.5, 0.0)::float8 as staffed_billable_hours,
       coalesce(sum(t.billable_hours)/60.0, 0.0)::float8 as billable_hours,
       coalesce(sum(t.staffed_nonbillable_days) * 7.5, 0.0)::float8 as staffed_nonbillable_hours,
       coalesce(sum(t.non_billable_hours)/60.0, 0.0)::float8 as non_billable_hours,
       coalesce(sum(t.staffed_unavailable_days) * 7.5, 0.0)::float8 as staffed_unavailable_hours,
       coalesce(sum(t.unavailable_hours)/60.0, 0.0)::float8 as unavailable_hours,
       (select * from unregistered_days(start_date,end_date,e.id) u) as unregistered_days,
       ld.date,
       lc.created::date
    from employees e
    left join (
        select coalesce(uah.id, bh.id, nbh.id, sbd.id, snd.id, sud.id) as employee_id,
            uah.sum as unavailable_hours,
            bh.sum as billable_hours,
            nbh.sum as non_billable_hours,
            sbd.days as staffed_billable_days,
            snd.days as staffed_nonbillable_days,
            sud.days as staffed_unavailable_days
        from (
          select * from unavailable_hours_for_employees(start_date,end_date)
        ) uah
        full outer join (
          select * from billable_hours_for_employees(start_date,end_date)
        ) bh on uah.id = bh.id
        full outer join (
          select * from nonbillable_hours_for_employees(start_date,end_date)
        ) nbh on uah.id = nbh.id
        full outer join (
          select * from staffed_billable_days_for_employees(start_date,end_date)
        ) sbd on uah.id = sbd.id
        full outer join (
          select * from staffed_nonbillable_days_for_employees(start_date,end_date)
        ) snd on uah.id = snd.id
        full outer join (
          select * from staffed_unavailable_days_for_employees(start_date,end_date)
        ) sud on uah.id = sud.id
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

CREATE OR REPLACE FUNCTION public.fg_for_employee(emp_id integer, start_date date, end_date date)
 RETURNS TABLE(available_hours double precision, billable_hours double precision)
 LANGUAGE plpgsql
 STABLE STRICT
AS $function$
begin
  return query (
    select
    business_hours(greatest(e.date_of_employment, start_date), least(e.termination_date, end_date)) - coalesce(sum(employee.unavailable_hours)/60.0, 0.0)::float8 as available_hours,
	  coalesce(sum(employee.billable_hours)/60.0, 0.0)::float8 as billable_hours
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
        select * from billable_hours_for_employees(start_date,end_date)
	    ) nbh on uah.id = nbh.id

	) as employee on employee.employee_id = e.id

	where e.id = emp_id
	group by e.id
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.employee_weekly_fg(year integer, emp_id integer)
RETURNS TABLE(week_number integer, week_start date, available_hours double precision, billable_hours double precision)
LANGUAGE plpgsql
AS $function$
DECLARE
  weeks_in_year integer;
BEGIN
  SELECT EXTRACT(WEEK FROM MAKE_DATE(year, 12, 28))::integer INTO weeks_in_year;

  RETURN QUERY
  SELECT
    weeks.week_number,
    weeks.week_start,
    hours.available_hours,
    hours.billable_hours
  FROM (
    SELECT
      generate_series(1, weeks_in_year) AS week_number,
      to_date(concat(year, lpad(generate_series(1, weeks_in_year)::text, 2, '0')), 'iyyyiw') AS week_start
  ) AS weeks
  JOIN LATERAL (
    SELECT
      fg.available_hours,
      fg.billable_hours
    FROM public.fg_for_employee(emp_id, weeks.week_start, weeks.week_start + 6) AS fg
  ) AS hours ON true;
END;
$function$;
