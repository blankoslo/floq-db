-- =============================================================================
-- Integration tests for weekly_forecasted_fg_json().
--
--     psql -d floq -f functions/tests/weekly_forecasted_fg_test.sql
--
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.
--
-- SAFE TO RUN ANYWHERE. Everything happens inside a transaction that is rolled
-- back at the end. Unlike the other test files this one clears the whole
-- company's week rather than one person's, because FG is a company figure —
-- the rollback is what makes that safe.
--
-- What is under test is the numerator's cap. `staffing` holds a plan that may
-- be longer than the week can hold: a project row is written on every weekday,
-- holidays included, so five days reads back as five. Those rows are intent.
-- The hours they become are capped at the days the person actually has.
-- =============================================================================

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

  -- From get_employees_in_dates, not from `employees`: this figure divides by
  -- who is employed that week, and apply_weekly_staffing has no employment
  -- check of its own. Somebody outside the window would land in the numerator
  -- and not the denominator, and every expectation below would be wrong.
  SELECT employee_id INTO emp
    FROM get_employees_in_dates(week_start, (week_start + 6)::date)
   ORDER BY employee_id LIMIT 1;
  ASSERT emp IS NOT NULL, 'setup: need an employee active in 2099-10';

  -- A company-wide figure needs a company-wide clean slate.
  DELETE FROM staffing WHERE date BETWEEN week_start AND (week_start + 6)::date;
  DELETE FROM absence  WHERE date BETWEEN week_start AND (week_start + 6)::date;
  DELETE FROM holidays WHERE "date" BETWEEN week_start AND (week_start + 6)::date;

  SELECT COUNT(*)::numeric INTO n_emp
    FROM get_employees_in_dates(week_start, (week_start + 6)::date);
  ASSERT n_emp > 0, 'setup: need employees active in 2099-10';

  SELECT COUNT(*)::numeric INTO wdc
    FROM available_dates_new(week_start, (week_start + 6)::date);
  ASSERT wdc = 5, 'setup: expected a holiday-free week in 2099, got ' || wdc;

  -- ===========================================================================
  -- 1. an empty week is 0 %
  -- ===========================================================================
  fg := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  ASSERT fg = 0, '1: an empty week is 0, got ' || fg;

  -- ===========================================================================
  -- 2. a full billable week, no holiday
  -- ===========================================================================
  -- One person booked 5 of 5 days. 37,5 billable hours against a company
  -- potential of n * 5 * 7,5.
  PERFORM apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
            'employee', emp, 'week', wk, 'project', p1, 'days', 5)));

  fg       := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  expected := ROUND(37.5 / (n_emp * 5 * 7.5) * 100, 1);
  ASSERT fg = expected, '2: expected ' || expected || ', got ' || fg;

  -- ===========================================================================
  -- 3. a holiday does not shrink a plan that still fits
  -- ===========================================================================
  -- THE REGRESSION. Three days booked in a week holding a red day is written
  -- as five rows of 60 %, because the plan is measured against the length of
  -- the week. Dropping the holiday row leaves 4 * 60 % = 18 hours, where the
  -- plan is three days and three days still fit in the four that remain. The
  -- cap is what gets this right: LEAST(3, 4) = 3 days = 22,5 hours.
  --
  -- personFg.ts in floq-staffing-v3 reaches 22,5 the same way, and the grid and
  -- this figure have to agree.
  DELETE FROM staffing WHERE date BETWEEN week_start AND (week_start + 6)::date;
  INSERT INTO holidays ("date", "name") VALUES (wednesday, 'Testfridag');

  PERFORM apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
            'employee', emp, 'week', wk, 'project', p1, 'days', 3)));

  -- the plan is five rows, one of them on the holiday
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

  -- ===========================================================================
  -- 4. a plan longer than the week is capped, not counted
  -- ===========================================================================
  -- Five days booked into a week holding four. The fifth will not happen, so it
  -- is not hours: LEAST(5, 4) = 4 days = 30 hours, and the person reads as
  -- fully booked rather than 125 %.
  DELETE FROM staffing WHERE date BETWEEN week_start AND (week_start + 6)::date;

  PERFORM apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
            'employee', emp, 'week', wk, 'project', p1, 'days', 5)));

  fg       := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  expected := ROUND(30.0 / (n_emp * 4 * 7.5) * 100, 1);
  ASSERT fg = expected,
         '4: a 5-day plan in a 4-day week is 30 h, not 37,5 — expected '
         || expected || ', got ' || fg;

  -- ===========================================================================
  -- 5. ferie leaves both sides; a fagdag leaves only the numerator
  -- ===========================================================================
  -- Unchanged by any of the above, and the reason the cap subtracts absence
  -- from what a person has rather than from the plan.
  DELETE FROM staffing WHERE date BETWEEN week_start AND (week_start + 6)::date;
  DELETE FROM holidays WHERE "date" = wednesday;

  PERFORM apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
            'employee', emp, 'week', wk, 'project', p1, 'days', 5)));
  INSERT INTO absence (employee_id, date, reason, percentage)
       VALUES (emp, week_start, 'FER1000', 100);

  -- 4 billable days left, against a potential one day shorter for this person
  fg       := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  expected := ROUND(30.0 / (n_emp * 5 * 7.5 - 7.5) * 100, 1);
  ASSERT fg = expected,
         '5: ferie leaves both sides — expected ' || expected || ', got ' || fg;

  DELETE FROM absence WHERE employee_id = emp AND date = week_start;
  INSERT INTO absence (employee_id, date, reason, percentage)
       VALUES (emp, week_start, 'FAG1000', 100);

  -- same 4 billable days, but a fagdag is time Blank had and spent on itself,
  -- so the denominator keeps it and FG falls
  fg       := (weekly_forecasted_fg_json(week_start, week_start)->>wk)::numeric;
  expected := ROUND(30.0 / (n_emp * 5 * 7.5) * 100, 1);
  ASSERT fg = expected,
         '5: a fagdag costs FG — expected ' || expected || ', got ' || fg;

  RAISE NOTICE 'weekly_forecasted_fg_json: all scenarios passed';
END
$test$;

ROLLBACK;
