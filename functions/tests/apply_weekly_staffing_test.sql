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
  nb         text;
  wk         text := '2099-10';
  week_start date;
  cap        integer;
  res        jsonb;
  undo       jsonb;
  d1         integer;
  d2         integer;
  ferie_rows integer;
  holiday_rows integer;
BEGIN
  SELECT id INTO emp FROM employees ORDER BY id LIMIT 1;
  ASSERT emp IS NOT NULL, 'setup: need at least one employee';

  SELECT id INTO p1 FROM projects
   WHERE billable = 'billable' AND NOT is_absence_reason(id) ORDER BY id LIMIT 1;
  SELECT id INTO p2 FROM projects
   WHERE billable = 'billable' AND NOT is_absence_reason(id) AND id <> p1 ORDER BY id LIMIT 1;
  ASSERT p1 IS NOT NULL AND p2 IS NOT NULL, 'setup: need two non-absence projects';

  week_start := to_date(wk || '-1', 'IYYY-IW-ID');
  -- available_dates_new() here on purpose, as a precondition rather than the
  -- capacity rule: 5 means the week holds no holidays, so scenarios that do not
  -- mention one start from a clean slate. apply_weekly_staffing() itself now
  -- measures capacity with weekday_dates().
  SELECT COUNT(*)::integer INTO cap FROM available_dates_new(week_start, (week_start + 4)::date);
  ASSERT cap = 5, 'setup: expected a holiday-free week in 2099, got ' || cap;

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
  -- 2. booking a second project displaces NOTHING
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

  ASSERT d1 = 3, '2: FIRST PROJECT KEEPS ITS DAYS, got ' || COALESCE(d1::text,'null');
  ASSERT d2 = 3, '2: second project should be 3, got '    || COALESCE(d2::text,'null');
  ASSERT (SELECT SUM(percentage) FROM staffing
           WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date) = 600,
         '2: so the week totals 6 days, and is overbooked on purpose';
  ASSERT jsonb_array_length(res->'weeks'->0->'displaced') = 0, '2: nothing displaced';

  -- ===========================================================================
  -- 3. ferie is never touched, and never clips the booking either
  -- ===========================================================================
  -- The full ask is written. Ferie is a fact about the person, not a smaller
  -- number to save in place of what somebody asked for — she may cancel it, and
  -- then the week has to be the week Knut planned. How much of it will actually
  -- happen comes back in `absence`.
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  INSERT INTO absence (employee_id, date, reason)
  SELECT emp, available_date, 'FER1000'
    FROM available_dates_new(week_start, (week_start + 3)::date);   -- 4 days

  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 3)));

  ASSERT (res->>'applied_weeks')::int = 1, '3: saved';
  ASSERT (res->>'refused_weeks')::int = 0, '3: and not a refusal';
  ASSERT jsonb_array_length(res->'weeks'->0->'refused') = 0,
         '3: ferie refuses nothing, got ' || (res->'weeks'->0->'refused')::text;
  ASSERT (res->'weeks'->0->'absence'->>'days')::int = 4, '3: 4 days away';
  ASSERT (res->'weeks'->0->'absence'->>'hidden_days')::int = 2,
         '3: 1 day is free, so 2 of the 3 will not happen, got '
         || (res->'weeks'->0->'absence'->>'hidden_days');
  ASSERT (res->'weeks'->0->'absence'->>'protected')::boolean, '3: ferie is protected';

  SELECT COUNT(*) INTO ferie_rows FROM absence
   WHERE employee_id = emp AND reason = 'FER1000'
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT ferie_rows = 4, '3: FERIE MUST BE UNTOUCHED, found ' || ferie_rows || ' rows';

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT COALESCE(d1, 0) = 3, '3: all 3 days should be recorded, got ' || COALESCE(d1::text,'0');

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
  ASSERT d1 = 5, '5: first project is untouched by the second booking, got '
                 || COALESCE(d1::text,'null');

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
  -- 8. a holiday does not shorten the plan
  -- ===========================================================================
  -- A project row is intent, measured against the length of the week. A red day
  -- on the Wednesday does not make the week four days long, it makes one of the
  -- five not happen — and the person row is where that gets subtracted. So the
  -- 5 days are granted whole, nothing is refused, and a row is written on the
  -- holiday itself so the plan reads back at the length it was made.
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  INSERT INTO holidays ("date", "name")
  SELECT (week_start + 2)::date, 'Testfridag'
  WHERE NOT EXISTS (SELECT 1 FROM holidays WHERE "date" = (week_start + 2)::date);

  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 5)));

  ASSERT (res->>'applied_weeks')::int = 1, '8: granted in full';
  ASSERT (res->>'refused_weeks')::int = 0, '8: and not a refusal';
  ASSERT jsonb_array_length(res->'weeks'->0->'refused') = 0,
         '8: a holiday is not a shortfall';

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT d1 = 5, '8: the plan is 5 days, got ' || COALESCE(d1::text,'null');

  SELECT COUNT(*)::integer INTO holiday_rows
    FROM staffing WHERE employee = emp AND project = p1
     AND date = (week_start + 2)::date;
  ASSERT holiday_rows = 1,
         '8: and one of the five sits on the holiday, got ' || holiday_rows;

  -- The shortfall path still exists — it just takes asking for more than the
  -- week is long. A partial grant is a save: counting it as a refusal made a
  -- batch that filled every cell announce "nothing saved".
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;

  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 6)));

  ASSERT (res->>'applied_weeks')::int = 1,
         '8: a partial grant is a save, got applied=' || (res->>'applied_weeks');
  ASSERT (res->>'refused_weeks')::int = 0, '8: and not a refusal';
  ASSERT (res->'weeks'->0->'refused'->0->>'granted_days')::int = 5, '8: 5 of 6 granted';
  ASSERT (res->'weeks'->0->'refused'->0->>'shortfall_days')::int = 1, '8: 1 over';

  DELETE FROM holidays WHERE "date" = (week_start + 2)::date;

  -- A week that is entirely ferie is still a save. Nothing of it will happen
  -- while the ferie stands, and `hidden_days` says so — but the plan is what was
  -- asked for, and it is what she comes back to if she cancels.
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  INSERT INTO absence (employee_id, date, reason)
  SELECT emp, available_date, 'FER1000'
    FROM available_dates_new(week_start, (week_start + 4)::date);

  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 3)));
  ASSERT (res->>'applied_weeks')::int = 1, '8: a full week of ferie is still a save';
  ASSERT (res->>'refused_weeks')::int = 0, '8: and not a refusal';
  ASSERT (res->'weeks'->0->'absence'->>'hidden_days')::int = 3,
         '8: none of the 3 days will happen';

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT COALESCE(d1, 0) = 3, '8: and it is on record, got ' || COALESCE(d1::text,'0');

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

  -- and the third day is genuinely gone: the week only has two free days, so
  -- asking for 3 records 3 and reports one of them as hidden
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p1, 'days', 3)));
  ASSERT (res->'weeks'->0->'absence'->>'days')::int = 3,
         '9: three DATES are away, not the four the two reasons would sum to';
  ASSERT (res->'weeks'->0->'absence'->>'hidden_days')::int = 1,
         '9: the week holds two, so the third day is hidden, got '
         || (res->'weeks'->0->'absence'->>'hidden_days');

  -- ===========================================================================
  -- 10. THE REGRESSION THIS CHANGE EXISTS FOR
  -- ===========================================================================
  -- A full week, then absence lands on it, then somebody edits ONE cell for an
  -- unrelated project. The first project's rows must still be there afterwards.
  --
  -- Before: the edit settled the whole week around the ferie and saved it, so p1
  -- went from 5 days to 2 in the table. Cancelling the ferie left her on 2 with
  -- nothing recording that 3 days had ever been planned — and the edit that did
  -- it never mentioned p1 at all.
  DELETE FROM staffing WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date;
  DELETE FROM absence  WHERE employee_id = emp AND date BETWEEN week_start AND (week_start + 4)::date;

  PERFORM apply_weekly_staffing(
            jsonb_build_array(jsonb_build_object(
              'employee', emp, 'week', wk, 'project', p1, 'days', 5)));

  INSERT INTO absence (employee_id, date, reason)
  SELECT emp, available_date, 'FER1000'
    FROM available_dates_new(week_start, (week_start + 1)::date);   -- Mon, Tue

  -- one unrelated day, on a different project
  res := apply_weekly_staffing(
           jsonb_build_array(jsonb_build_object(
             'employee', emp, 'week', wk, 'project', p2, 'days', 1)));

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d2
    FROM staffing WHERE employee = emp AND project = p2
     AND date BETWEEN week_start AND (week_start + 4)::date;

  -- p1 gives up NOTHING. Neither the ferie nor the unrelated booking takes a
  -- day off a project the edit never mentioned.
  ASSERT d1 = 5, '10: p1 MUST LOSE NOTHING AT ALL, got '
                 || COALESCE(d1::text,'null');
  ASSERT d2 = 1, '10: p2 booked, got ' || COALESCE(d2::text,'null');
  -- 6 days planned, 3 left after the ferie, so 3 will not happen.
  ASSERT (res->'weeks'->0->'absence'->>'hidden_days')::int = 3,
         '10: 3 of the 6 planned days cannot happen, got '
         || (res->'weeks'->0->'absence'->>'hidden_days');

  -- now she cancels the ferie: the week is full again, with no repair
  DELETE FROM absence WHERE employee_id = emp
     AND date BETWEEN week_start AND (week_start + 4)::date;

  SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
    FROM staffing WHERE employee = emp AND project = p1
     AND date BETWEEN week_start AND (week_start + 4)::date;
  ASSERT d1 = 5, '10: THE PLAN MUST SURVIVE THE FERIE, got ' || COALESCE(d1::text,'null');
  ASSERT (SELECT SUM(percentage) FROM staffing
           WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date) = 600,
         '10: and the week is exactly what was asked for, ferie or no ferie';

  -- ===========================================================================
  -- 11. an internal code is no different from a client one
  --
  -- It used to be: a two-budget version of this rule looked `billable` up in
  -- `projects` and gave internal work a week of its own. That is gone — nothing
  -- displaces anything, so there is nothing for the two budgets to separate.
  -- The case stays because it is the shape a planner actually books, and it
  -- would catch a return to shaving from either direction.
  -- ===========================================================================
  SELECT id INTO nb FROM projects
   WHERE billable = 'nonbillable' AND NOT is_absence_reason(id) ORDER BY id LIMIT 1;

  IF nb IS NULL THEN
    RAISE NOTICE '11: SKIPPED — no bookable nonbillable project in this database';
  ELSE
    DELETE FROM staffing WHERE employee = emp
       AND date BETWEEN week_start AND (week_start + 4)::date;

    -- a full week of client work
    PERFORM apply_weekly_staffing(
              jsonb_build_array(jsonb_build_object(
                'employee', emp, 'week', wk, 'project', p1, 'days', 5)));

    -- ...then a day of internal time
    res := apply_weekly_staffing(
             jsonb_build_array(jsonb_build_object(
               'employee', emp, 'week', wk, 'project', nb, 'days', 1)));

    SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d1
      FROM staffing WHERE employee = emp AND project = p1
       AND date BETWEEN week_start AND (week_start + 4)::date;
    SELECT ROUND(SUM(percentage) / 100.0)::integer INTO d2
      FROM staffing WHERE employee = emp AND project = nb
       AND date BETWEEN week_start AND (week_start + 4)::date;

    ASSERT d1 = 5, '11: THE CLIENT ENGAGEMENT KEEPS ITS WEEK, got '
                   || COALESCE(d1::text,'null');
    ASSERT d2 = 1, '11: and the internal day is booked, got '
                   || COALESCE(d2::text,'null');
    ASSERT jsonb_array_length(res->'weeks'->0->'displaced') = 0,
           '11: nothing displaced';
    ASSERT jsonb_array_length(res->'weeks'->0->'refused') = 0,
           '11: nothing refused';
    -- 6 days of plan in a 5-day week, on purpose
    ASSERT (SELECT SUM(percentage) FROM staffing
             WHERE employee = emp AND date BETWEEN week_start AND (week_start + 4)::date) = 600,
           '11: the week reads 6 of 5 and says so';
  END IF;

  RAISE NOTICE 'apply_weekly_staffing: all 11 scenarios passed';
END
$test$;

ROLLBACK;
