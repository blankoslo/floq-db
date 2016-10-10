-- Revert floq:update_timetracking_status_function_add_commit_date from pg

BEGIN;

drop function time_tracking_status(date, date);

create or replace function business_hours(start_date date, end_date date, hours_per_day float8 default 7.5)
returns float8
as $$
  select count(date)*7.5::float8 from (
      select *
      from generate_series(start_date, end_date, '1 day'::interval) as date
      where extract(dow from date) between 1 and 5
        except
      select date from holidays
  ) as date;
$$
language sql stable strict;

create or replace function time_tracking_status(start_date date, end_date date)
returns TABLE (
    name text,
    available_hours float8,
    billable_hours float8)
as $$
begin
  return query (
    select e.first_name || ' ' || e.last_name,
           business_hours(greatest(e.date_of_employment, start_date), least(e.termination_date, end_date)) - coalesce(sum(t.unavailable_hours)/60.0, 0.0)::float8,
           coalesce(sum(t.billable_hours)/60.0, 0.0)::float8
    from (
        select coalesce(uah.employee, bh.employee) as employee,
               uah.sum as unavailable_hours,
               bh.sum as billable_hours
        from (
            -- find sum of unavailable time (holidays, vacation days, sick leave, etc.) per employee
            select t.employee, sum(minutes)
            from time_entry t,
                 projects p
            where t.project = p.id
              and t.date between start_date and end_date
              and p.billable = 'unavailable'
            group by t.employee
        ) uah
        full outer join (
            -- find sum of billable hours worked per employee
            select t.employee, sum(minutes)
            from time_entry t,
                 projects p
            where t.project = p.id
              and t.date between start_date and end_date
              and p.billable = 'billable'
            group by t.employee
        ) bh
        on uah.employee = bh.employee) as t
    -- include all employees
    right join employees e
    on t.employee = e.id
    where e.date_of_employment <= start_date
      and (e.termination_date is null or e.termination_date > start_date)
    group by e.id
    order by name
  );
end
$$
language plpgsql immutable strict;

COMMIT;
