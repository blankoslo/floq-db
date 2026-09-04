insert into employees (id, first_name, last_name) values
  (1,'Rate changes midweek',''),
  (2,'No rate at all',''),
  (3,'Duplicate rate rows',''),
  (4,'Rate starts midweek',''),
  (5,'Rate starts after the week','');

insert into customers (id, name) values ('aid','Aid AS'), ('bnk','Bank AS');

insert into projects (id, name, billable, customer) values
  ('aid1','Aid billable','billable','aid'),
  ('aid2','Aid internal','nonbillable','aid'),
  ('bnk1','Bank billable','billable','bnk');

insert into project_members (id, employee_id, customer_id, hourly_rate, from_date) values
  ('r1',1,'aid',1000,'2026-01-01'),
  ('r2',1,'aid',1200,'2026-08-05'),
  ('r3',3,'bnk',1500,'2026-02-01'),
  ('r4',3,'bnk',1500,'2026-02-01'),
  ('r5',4,'aid', 900,'2026-08-06'),
  ('r6',5,'aid', 800,'2026-09-01');

insert into time_entry (employee, minutes, project, date) values
  (1,450,'aid1','2026-08-03'),
  (1,450,'aid1','2026-08-04'),
  (1,450,'aid1','2026-08-05'),
  (1,450,'aid1','2026-08-06'),
  (1,450,'aid1','2026-08-07'),
  (1,180,'aid2','2026-08-03'),
  (1,450,'aid1','2026-08-11'),
  (1,450,'aid1','2026-08-12'),
  (2,450,'aid1','2026-08-03'),
  (3,450,'bnk1','2026-08-03'),
  (4,450,'aid1','2026-08-03'),
  (4,450,'aid1','2026-08-04'),
  (4,450,'aid1','2026-08-06'),
  (4,450,'aid1','2026-08-07'),
  (5,450,'aid1','2026-08-03');

do $$
declare
  actual text;
  expected text;
begin
  select string_agg(
           format('%s|%s|%s|%s|%s|%s',
                  employee_id, week_start, customer_id, hours, amount, hours_missing_rate),
           E'\n' order by week_start, employee_id, customer_id)
    into actual
  from company_week_revenue('2026-08-05','2026-08-12');

  expected := concat_ws(E'\n',
    '1|2026-08-03|aid|37.5|42000.0000000000000000|0',
    '2|2026-08-03|aid|7.5|0.0000000000000000|7.5',
    '3|2026-08-03|bnk|7.5|11250.0000000000000000|0',
    '4|2026-08-03|aid|30|13500.0000000000000000|15',
    '5|2026-08-03|aid|7.5|0.0000000000000000|7.5',
    '1|2026-08-10|aid|15|18000.0000000000000000|0');

  if actual is distinct from expected then
    raise exception E'company_week_revenue mismatch\nexpected:\n%\nactual:\n%', expected, actual;
  end if;

  raise notice 'company_week_revenue ok';
end $$;

do $$
declare
  actual text;
begin
  select string_agg(format('%s|%s|%s', period_start, period_end, hourly_rate), ' ' order by period_start)
    into actual
  from employee_rate_periods('2026-08-03','2026-08-09','aid')
  where employee_id = 1;

  if actual is distinct from '2026-08-03|2026-08-04|1000 2026-08-05|2026-08-09|1200' then
    raise exception 'employee_rate_periods mismatch: %', actual;
  end if;

  raise notice 'employee_rate_periods ok';
end $$;
