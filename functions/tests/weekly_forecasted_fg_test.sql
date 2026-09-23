-- Integration tests for weekly_forecasted_fg_json(): planned days are capped at
-- the days a person actually has.
--
--     psql -d floq -f functions/tests/weekly_forecasted_fg_test.sql
--
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.

BEGIN;

DO $test$
DECLARE
  emp        integer;
  p1         text;
  wk         text := '2099-10';
  week_start date;
  wednesday  date;
  n_emp      numeric;
  wdc        numeric;
  fg         numeric;
  expected   numeric;
BEGIN
  SELECT id INTO p1 FROM projects
   WHERE billable = 'billable' AND NOT is_absence_reason(id) ORDER BY id LIMIT 1;
  ASSERT p1 IS NOT NULL, 'setup: need a billable project';

  week_start := to_date(wk || '-1', 'IYYY-IW-ID');
  wednesday  := (week_start + 2)::date;

  -- from get_employees_in_dates so emp is also counted in the denominator
  SELECT employee_id INTO emp
    FROM get_employees_in_dates(week_start, (week_start + 6)::date)
   ORDER BY employee_id LIMIT 1;
  ASSERT emp IS NOT NULL, 'setup: need an employee active in 2099-10';

  DELETE FROM staffing WHERE date BETWEEN week_start AND (week_start + 6)::date;
  DELETE FROM absence  WHERE date BETWEEN week_start AND (week_start + 6)::date;
  DELETE FROM holidays WHERE "date" BETWEEN week_start AND (week_start + 6)::date;

  SELECT COUNT(*)::numeric INTO n_emp
    FROM get_employees_in_dates(week_start, (week_start + 6)::date);
  ASSERT n_emp > 0, 'setup: need employees active in 2099-10';

  SELECT COUNT(*)::numeric INTO wdc
    FROM available_dates_new(week_start, (week_start + 6)::date);
  ASSERT wdc = 5, 'setup: expected a holiday-free week in 2099, got ' || wdc;

  -- 1. an empty week is 0 %
  fg := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  ASSERT fg = 0, '1: an empty week is 0, got ' || fg;

  -- 2. a full billable week, no holiday
  PERFORM apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
            'employee', emp, 'week', wk, 'project', p1, 'days', 5)));

  fg       := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  expected := ROUND(37.5 / (n_emp * 5 * 7.5) * 100, 1);
  ASSERT fg = expected, '2: expected ' || expected || ', got ' || fg;

  -- 3. a holiday does not shrink a plan that still fits
  -- 3 days are written as five rows of 60 %, one on the holiday
  DELETE FROM staffing WHERE date BETWEEN week_start AND (week_start + 6)::date;
  INSERT INTO holidays ("date", "name") VALUES (wednesday, 'Testfridag');

  PERFORM apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
            'employee', emp, 'week', wk, 'project', p1, 'days', 3)));

  ASSERT (SELECT COUNT(*) FROM staffing
           WHERE employee = emp AND project = p1
             AND date BETWEEN week_start AND (week_start + 4)::date) = 5,
         '3: the plan is written on all five weekdays';
  ASSERT (SELECT COUNT(*) FROM staffing
           WHERE employee = emp AND project = p1 AND date = wednesday) = 1,
         '3: including the holiday itself';

  fg       := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  expected := ROUND(22.5 / (n_emp * 4 * 7.5) * 100, 1);
  ASSERT fg = expected,
         '3: a 3-day plan in a holiday week is 22,5 h, not 18 — expected '
         || expected || ', got ' || fg;

  -- 4. a plan longer than the week is capped, not counted
  DELETE FROM staffing WHERE date BETWEEN week_start AND (week_start + 6)::date;

  PERFORM apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
            'employee', emp, 'week', wk, 'project', p1, 'days', 5)));

  fg       := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  expected := ROUND(30.0 / (n_emp * 4 * 7.5) * 100, 1);
  ASSERT fg = expected,
         '4: a 5-day plan in a 4-day week is 30 h, not 37,5 — expected '
         || expected || ', got ' || fg;

  -- 5. ferie leaves both sides; a fagdag leaves only the numerator
  DELETE FROM staffing WHERE date BETWEEN week_start AND (week_start + 6)::date;
  DELETE FROM holidays WHERE "date" = wednesday;

  PERFORM apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
            'employee', emp, 'week', wk, 'project', p1, 'days', 5)));
  INSERT INTO absence (employee_id, date, reason, percentage)
       VALUES (emp, week_start, 'FER1000', 100);

  fg       := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  expected := ROUND(30.0 / (n_emp * 5 * 7.5 - 7.5) * 100, 1);
  ASSERT fg = expected,
         '5: ferie leaves both sides — expected ' || expected || ', got ' || fg;

  DELETE FROM absence WHERE employee_id = emp AND date = week_start;
  INSERT INTO absence (employee_id, date, reason, percentage)
       VALUES (emp, week_start, 'FAG1000', 100);

  fg       := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  expected := ROUND(30.0 / (n_emp * 5 * 7.5) * 100, 1);
  ASSERT fg = expected,
         '5: a fagdag costs FG — expected ' || expected || ', got ' || fg;

  RAISE NOTICE 'weekly_forecasted_fg_json: all scenarios passed';
END
$test$;

ROLLBACK;
