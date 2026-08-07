-- =============================================================================
-- Integration tests for apply_weekly_staffing() and restore_weekly_staffing().
--
--     psql -d floq -f functions/tests/apply_weekly_staffing_test.sql
--
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.
--
-- SAFE TO RUN ANYWHERE. Everything happens inside a transaction that is rolled
-- back at the end, and it borrows an existing employee and two existing
-- projects rather than inventing rows (the real employees table has a dozen
-- NOT NULL columns). The week used is in 2099, so it is certainly empty.
-- =============================================================================

BEGIN;

DO $test$
DECLARE
  emp        integer;
  p1         text;
  p2         text;
  wk         text := '2099-10';
  week_start date;
  cap        integer;
  res        jsonb;
  undo       jsonb;
  d1         integer;
  d2         integer;
  ferie_rows integer;
BEGIN
  SELECT id INTO emp FROM employees ORDER BY id LIMIT 1;
  ASSERT emp IS NOT NULL, 'setup: need at least one employee';

  SELECT id INTO p1 FROM projects
   WHERE billable = 'billable' AND NOT is_absence_reason(id) ORDER BY id LIMIT 1;
  SELECT id INTO p2 FROM projects
   WHERE billable = 'billable' AND NOT is_absence_reason(id) AND id <> p1 ORDER BY id LIMIT 1;
  ASSERT p1 IS NOT NULL AND p2 IS NOT NULL, 'setup: need two non-absence projects';

  week_start := to_date(wk || '-1', 'IYYY-IW-ID');
  SELECT COUNT(*)::integer INTO cap FROM available_dates_new(week_start, (week_start + 4)::date);
  ASSERT cap = 5, 'setup: expected a clean 5-day week in 2099, got ' || cap;

  -- start from a known-empty week
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  DELETE FROM absence  WHERE employee_id = emp AND date BETWEEN week_start AND (week_start + 4)::date;

  -- ===========================================================================
  -- 1. a plain booking, and the days <-> percent round trip
  -- ===========================================================================
  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 3)));

  ASSERT (res->>'applied_weeks')::int = 1, '1: one week applied';
  ASSERT (res->>'refused_weeks')::int = 0, '1: nothing refused';

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT d1 = 3, '1: should read back as 3 days, got ' || COALESCE(d1::text,'null');

  -- written as a uniform percentage across the week's working days
  ASSERT (SELECT COUNT(DISTINCT percentage) FROM staffing
           WHERE employee = emp AND project = p1
             AND date BETWEEN week_start AND (week_start + 4)::date) = 1,
         '1: percentage should be uniform across the week';
  ASSERT (SELECT MAX(percentage) FROM staffing
           WHERE employee = emp AND project = p1
             AND date BETWEEN week_start AND (week_start + 4)::date) = 60,
         '1: 3 of 5 days is 60% per day';

  -- ===========================================================================
  -- 2. booking a second project displaces the first
  -- ===========================================================================
  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p2, 'days', 3)));

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d2
    FROM staffing WHERE employee = emp AND project = p2
     AND date BETWEEN week_start AND (week_start + 4)::date;

  ASSERT d1 = 2, '2: first project should drop to 2, got ' || COALESCE(d1::text,'null');
  ASSERT d2 = 3, '2: second project should be 3, got '     || COALESCE(d2::text,'null');
  ASSERT (SELECT SUM(percentage) FROM staffing
           WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date) = 500,
         '2: the week must total exactly 5 days';

  -- ===========================================================================
  -- 3. ferie is never touched, and the shortfall is reported
  -- ===========================================================================
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  INSERT INTO absence (employee_id, date, reason)
  SELECT emp, available_date, 'FER1000'
    FROM available_dates_new(week_start, (week_start + 3)::date);   -- 4 days

  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 3)));

  -- One day fitted, so this is a partial save with a shortfall, not a refusal.
  -- Only a week that got nothing at all counts as refused.
  ASSERT (res->>'applied_weeks')::int = 1, '3: one day fitted, so it is a save';
  ASSERT (res->>'refused_weeks')::int = 0, '3: and not a refusal';
  ASSERT res->'weeks'->0->'refused'->0->>'reason' = 'blocked_by_protected_absence',
         '3: wrong reason: ' || COALESCE(res->'weeks'->0->'refused'->0->>'reason','null');
  ASSERT (res->'weeks'->0->'refused'->0->>'shortfall_days')::int = 2, '3: 2 days should not fit';

  SELECT COUNT(*) INTO ferie_rows FROM absence
   WHERE employee_id = emp AND reason = 'FER1000'
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT ferie_rows = 4, '3: FERIE MUST BE UNTOUCHED, found ' || ferie_rows || ' rows';

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT COALESCE(d1, 0) = 1, '3: only 1 day should fit, got ' || COALESCE(d1::text,'0');

  -- ===========================================================================
  -- 4. dry run changes nothing
  -- ===========================================================================
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  DELETE FROM absence  WHERE employee_id = emp AND date BETWEEN week_start AND (week_start + 4)::date;

  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 4)), true);

  ASSERT (res->>'dry_run')::boolean, '4: should be flagged as a dry run';
  ASSERT (res->'weeks'->0->'allocations'->0->>'days')::int = 4, '4: should still plan 4 days';
  ASSERT NOT EXISTS (SELECT 1 FROM staffing
                      WHERE employee = emp
                        AND date BETWEEN week_start AND (week_start + 4)::date),
         '4: A DRY RUN MUST NOT WRITE ANYTHING';

  -- ===========================================================================
  -- 5. undo puts the week back exactly as it was
  -- ===========================================================================
  PERFORM apply_weekly_staffing(
            jsonb_build_array(jsonb_build_object(
              'employee', emp, 'week', wk, 'project', p1, 'days', 5)));

  res  := apply_weekly_staffing(
            jsonb_build_array(jsonb_build_object(
              'employee', emp, 'week', wk, 'project', p2, 'days', 2)));
  undo := res->'undo';

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT d1 = 3, '5: first project should be 3 after the second booking';

  res := restore_weekly_staffing(undo);
  ASSERT (res->>'restored_weeks')::int = 1, '5: one week restored';

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT d1 = 5, '5: first project should be back to 5, got ' || COALESCE(d1::text,'null');
  ASSERT NOT EXISTS (SELECT 1 FROM staffing
                      WHERE employee = emp AND project = p2
                        AND date BETWEEN week_start AND (week_start + 4)::date),
         '5: the project the undone batch created must be gone again';

  -- ===========================================================================
  -- 6. undo declines to trample someone else's edit
  -- ===========================================================================
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  PERFORM apply_weekly_staffing(
            jsonb_build_array(jsonb_build_object(
              'employee', emp, 'week', wk, 'project', p1, 'days', 4)));
  res  := apply_weekly_staffing(
            jsonb_build_array(jsonb_build_object(
              'employee', emp, 'week', wk, 'project', p2, 'days', 1)));
  undo := res->'undo';

  -- somebody else changes the same week in the meantime
  PERFORM apply_weekly_staffing(
            jsonb_build_array(jsonb_build_object(
              'employee', emp, 'week', wk, 'project', p2, 'days', 3)));

  res := restore_weekly_staffing(undo);
  ASSERT (res->>'skipped_weeks')::int = 1, '6: should skip the changed week';
  ASSERT res->'weeks'->0->>'status' = 'changed_since', '6: wrong status';

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d2
    FROM staffing WHERE employee = emp AND project = p2
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT d2 = 3, '6: THE OTHER PERSON''S EDIT MUST SURVIVE, got ' || COALESCE(d2::text,'null');

  -- ===========================================================================
  -- 7. one bad row does not sink the batch
  -- ===========================================================================
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;

  res := apply_weekly_staffing(jsonb_build_array(
           jsonb_build_object('employee', emp, 'week', wk,       'project', p1,        'days', 2),
           jsonb_build_object('employee', emp, 'week', '2099-11', 'project', 'FER1000','days', 3)));

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT d1 = 2, '7: the good row must still be saved, got ' || COALESCE(d1::text,'null');
  ASSERT (res->>'refused_weeks')::int = 1, '7: the bad row should be reported as refused';

  -- ===========================================================================
  -- 8. a short week counts as saved, not refused
  -- ===========================================================================
  -- Asking for 5 days in a week that only holds 4 grants 4 and reports a
  -- shortfall. That is a save. Counting it as a refusal made a batch that
  -- filled every cell announce "nothing saved".
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  INSERT INTO holidays ("date", "name")
  SELECT (week_start + 2)::date, 'Testfridag'
  WHERE NOT EXISTS (SELECT 1 FROM holidays WHERE "date" = (week_start + 2)::date);

  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 5)));

  ASSERT (res->>'applied_weeks')::int = 1,
         '8: a partial grant is a save, got applied=' || (res->>'applied_weeks');
  ASSERT (res->>'refused_weeks')::int = 0, '8: and not a refusal';
  ASSERT (res->'weeks'->0->'refused'->0->>'granted_days')::int = 4, '8: 4 of 5 granted';
  ASSERT (res->'weeks'->0->'refused'->0->>'shortfall_days')::int = 1, '8: 1 short';

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT d1 = 4, '8: the week is full at 4 days, got ' || COALESCE(d1::text,'null');

  -- and a week where NOTHING was granted is still a refusal
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  INSERT INTO absence (employee_id, date, reason)
  SELECT emp, available_date, 'FER1000'
    FROM available_dates_new(week_start, (week_start + 4)::date);

  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 3)));
  ASSERT (res->>'refused_weeks')::int = 1, '8: nothing granted is still refused';
  ASSERT (res->>'applied_weeks')::int = 0, '8: and not applied';

  -- ===========================================================================
  -- 9. a day carrying two kinds of absence is one day gone, not two
  -- ===========================================================================
  -- `absence` is keyed by (employee_id, reason, date), so one Tuesday can hold
  -- ferie and fagutvikling at once. Grouping the week by reason alone counted
  -- that Tuesday twice, so a person away Monday to Wednesday had four of five
  -- days locked instead of three — and one of the two days they were genuinely
  -- free for came back refused.
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  DELETE FROM absence  WHERE employee_id = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  DELETE FROM holidays WHERE "date" BETWEEN week_start AND (week_start + 4)::date;

  INSERT INTO absence (employee_id, date, reason)
  SELECT emp, available_date, 'FER1000'
    FROM available_dates_new(week_start, (week_start + 2)::date);   -- Mon-Wed
  INSERT INTO absence (employee_id, date, reason)
  VALUES (emp, (week_start + 1)::date, 'FAG1000');                  -- inside it

  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 2)));

  ASSERT (res->>'applied_weeks')::int = 1, '9: two free days are still bookable';
  ASSERT (res->>'refused_weeks')::int = 0, '9: and nothing is refused';
  ASSERT jsonb_array_length(res->'weeks'->0->'refused') = 0,
         '9: no shortfall either, got ' || (res->'weeks'->0->'refused')::text;

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT d1 = 2, '9: both days should fit, got ' || COALESCE(d1::text,'null');

  -- and the third day is genuinely gone: asking for 3 leaves one short
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 3)));
  ASSERT (res->'weeks'->0->'refused'->0->>'shortfall_days')::int = 1,
         '9: the week holds two, so the third day is short';

  RAISE NOTICE 'apply_weekly_staffing: all 9 scenarios passed';
END
$test$;

ROLLBACK;
