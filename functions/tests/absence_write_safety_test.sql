-- =============================================================================
-- Destructive-safety tests: what these writes must NEVER do.
--
--     psql -d floq -f functions/tests/absence_write_safety_test.sql
--
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.
--
-- SAFE TO RUN ANYWHERE. Everything happens inside a transaction that is rolled
-- back at the end. It works in a week in 2099, so it cannot collide with real
-- data, and every assertion is a checksum of the WHOLE table — the point is not
-- "did the rows I expected appear" (company_absence_test.sql covers that) but
-- "did anything else in the table move".
--
-- The question behind this file: apply_company_absence and
-- restore_company_absence are new, they are the first thing in this app allowed
-- to write `absence`, and restore issues a DELETE. A DELETE with a filter that
-- fails to bind is how a table gets emptied. So:
--
--   1. a booking must never modify `staffing`, and never touch an absence row
--      it did not create — including not overwriting its percentage
--   2. an undo must delete only the rows its own batch created, and must delete
--      NOTHING when handed an empty, malformed or hostile snapshot
--   3. apply_weekly_staffing must still never write `absence` at all, which is
--      the invariant the DISTINCT ON change had to preserve
-- =============================================================================

BEGIN;

-- ---- whole-table fingerprints ----------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.absence_sum() RETURNS text AS $$
  SELECT COALESCE(md5(string_agg(
           employee_id || '|' || date || '|' || reason || '|' || COALESCE(percentage::text, '-'),
           ',' ORDER BY employee_id, date, reason)), 'empty')
  FROM absence;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.staffing_sum() RETURNS text AS $$
  SELECT COALESCE(md5(string_agg(
           employee || '|' || date || '|' || project || '|' || percentage,
           ',' ORDER BY employee, date, project)), 'empty')
  FROM staffing;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.absence_rows() RETURNS bigint AS $$
  SELECT COUNT(*) FROM absence;
$$ LANGUAGE sql;

DO $test$
DECLARE
  e1        integer;
  e2        integer;
  e3        integer;
  p1        text;
  wk        text := '2099-20';
  monday    date;
  tuesday   date;
  wednesday date;
  res       jsonb;
  undo      jsonb;
  abs_before   text;
  abs_after    text;
  stf_before   text;
  stf_after    text;
  rows_before  bigint;
BEGIN
  SELECT id INTO e1 FROM employees ORDER BY id LIMIT 1;
  SELECT id INTO e2 FROM employees WHERE id <> e1 ORDER BY id LIMIT 1;
  SELECT id INTO e3 FROM employees WHERE id NOT IN (e1, e2) ORDER BY id LIMIT 1;
  SELECT id INTO p1 FROM projects
   WHERE billable = 'billable' AND NOT is_absence_reason(id) ORDER BY id LIMIT 1;
  ASSERT e3 IS NOT NULL AND p1 IS NOT NULL, 'setup: need three employees and a project';

  monday    := to_date(wk || '-1', 'IYYY-IW-ID');
  tuesday   := (monday + 1)::date;
  wednesday := (monday + 2)::date;

  DELETE FROM staffing WHERE date BETWEEN monday AND (monday + 6)::date;
  DELETE FROM absence  WHERE date BETWEEN monday AND (monday + 6)::date;
  DELETE FROM holidays WHERE "date" BETWEEN monday AND (monday + 6)::date;

  -- A week with something to lose: bookings for two people, three kinds of
  -- pre-existing absence, one of them a fagdag at a percentage nobody should
  -- rewrite, and one row on the day the batch will target.
  INSERT INTO staffing (employee, date, project, percentage)
  SELECT e1, available_date, p1, 100 FROM available_dates_new(monday, (monday + 4)::date);
  INSERT INTO staffing (employee, date, project, percentage)
  SELECT e3, available_date, p1, 60  FROM available_dates_new(monday, (monday + 4)::date);

  INSERT INTO absence (employee_id, date, reason) VALUES (e2, tuesday, 'FER1000');
  INSERT INTO absence (employee_id, date, reason) VALUES (e2, wednesday, 'AVS');
  INSERT INTO absence (employee_id, date, reason, percentage) VALUES (e3, tuesday, 'FAG1000', 50);

  -- ===========================================================================
  -- 1. a dry run writes nothing at all
  -- ===========================================================================
  abs_before := pg_temp.absence_sum();
  stf_before := pg_temp.staffing_sum();

  res := apply_company_absence('FAG1000', ARRAY[tuesday], ARRAY[e1, e2, e3], true);

  ASSERT pg_temp.absence_sum() = abs_before, '1: A DRY RUN WROTE TO absence';
  ASSERT pg_temp.staffing_sum() = stf_before, '1: A DRY RUN WROTE TO staffing';

  -- ===========================================================================
  -- 2. a real booking adds rows and changes nothing else
  -- ===========================================================================
  rows_before := pg_temp.absence_rows();
  res  := apply_company_absence('FAG1000', ARRAY[tuesday], ARRAY[e1, e2, e3], false);
  undo := res->'undo';

  -- e1 is free that day, e2 is on ferie (skipped), e3 already has the fagdag
  ASSERT (res->>'booked')::int = 1, '2: exactly one row should have been created';
  ASSERT pg_temp.absence_rows() = rows_before + 1,
         '2: the table grew by ' || (pg_temp.absence_rows() - rows_before) || ' rows, not 1';

  ASSERT pg_temp.staffing_sum() = stf_before, '2: A BOOKING MODIFIED staffing';

  ASSERT EXISTS (SELECT 1 FROM absence
                  WHERE employee_id = e2 AND date = tuesday AND reason = 'FER1000'),
         '2: somebody else''s ferie was removed';
  ASSERT EXISTS (SELECT 1 FROM absence
                  WHERE employee_id = e2 AND date = wednesday AND reason = 'AVS'),
         '2: an absence row on a different day was removed';
  ASSERT (SELECT percentage FROM absence
           WHERE employee_id = e3 AND date = tuesday AND reason = 'FAG1000') = 50,
         '2: AN EXISTING ROW''S PERCENTAGE WAS OVERWRITTEN';

  -- ===========================================================================
  -- 3. the undo puts the table back exactly, and leaves staffing alone
  -- ===========================================================================
  res := restore_company_absence(undo);

  ASSERT (res->>'removed')::int = 1, '3: one row removed';
  ASSERT pg_temp.absence_sum() = abs_before,
         '3: THE UNDO DID NOT RESTORE absence EXACTLY';
  ASSERT pg_temp.staffing_sum() = stf_before, '3: THE UNDO MODIFIED staffing';

  -- ===========================================================================
  -- 4. an undo handed nonsense deletes NOTHING
  -- ===========================================================================
  -- This is the case that would empty a table: a DELETE whose filters all bind
  -- to nothing is a DELETE of everything, and an undo is exactly where a
  -- half-built snapshot arrives.
  abs_before := pg_temp.absence_sum();

  res := restore_company_absence('{"reason":"FAG1000","rows":[]}'::jsonb);
  ASSERT (res->>'removed')::int = 0 AND pg_temp.absence_sum() = abs_before,
         '4: AN EMPTY SNAPSHOT DELETED ROWS';

  res := restore_company_absence('{"reason":"FAG1000"}'::jsonb);
  ASSERT pg_temp.absence_sum() = abs_before, '4: A SNAPSHOT WITH NO rows DELETED ROWS';

  res := restore_company_absence('{}'::jsonb);
  ASSERT pg_temp.absence_sum() = abs_before, '4: AN EMPTY OBJECT DELETED ROWS';

  res := restore_company_absence(NULL);
  ASSERT pg_temp.absence_sum() = abs_before, '4: A NULL SNAPSHOT DELETED ROWS';

  res := restore_company_absence('{"reason":null,"rows":[]}'::jsonb);
  ASSERT pg_temp.absence_sum() = abs_before, '4: A NULL REASON DELETED ROWS';

  -- ===========================================================================
  -- 5. an undo cannot be pointed at absence it did not create
  -- ===========================================================================
  -- The fraværskalender's own DELETE filters on employee and date only, so it
  -- takes whatever else is on that day with it. A snapshot naming somebody
  -- else's ferie must come back empty-handed rather than remove it.
  res := restore_company_absence(jsonb_build_object(
           'reason', 'FER1000',
           'rows', jsonb_build_array(jsonb_build_object('employee', e2, 'date', tuesday))));
  ASSERT res->>'refused' = 'not_bookable', '5: a non-bookable reason must be refused';
  ASSERT pg_temp.absence_sum() = abs_before, '5: A FERIE ROW WAS DELETED BY AN UNDO';

  -- ...and a well-formed snapshot for the right reason still only matches that
  -- reason, so the ferie on the same person-day survives.
  res := restore_company_absence(jsonb_build_object(
           'reason', 'FAG1000',
           'rows', jsonb_build_array(jsonb_build_object('employee', e2, 'date', tuesday))));
  ASSERT (res->>'removed')::int = 0 AND (res->>'skipped')::int = 1,
         '5: nothing of that reason was there to remove';
  ASSERT pg_temp.absence_sum() = abs_before, '5: THE FERIE ON THAT DAY WAS TAKEN INSTEAD';

  -- an unknown employee and an unreachable date are equally harmless
  res := restore_company_absence(jsonb_build_object(
           'reason', 'FAG1000',
           'rows', jsonb_build_array(
             jsonb_build_object('employee', 999999, 'date', tuesday),
             jsonb_build_object('employee', e1, 'date', '2099-12-31'))));
  ASSERT pg_temp.absence_sum() = abs_before, '5: A SNAPSHOT OF ROWS THAT DO NOT EXIST DELETED SOMETHING';

  -- ===========================================================================
  -- 6. a refused booking writes nothing
  -- ===========================================================================
  INSERT INTO holidays ("date", "name") VALUES (monday, 'Testfridag');

  res := apply_company_absence('FAG1000', ARRAY[monday], ARRAY[e1, e2, e3]);
  ASSERT res->>'refused' = 'not_a_working_day', '6: a holiday is refused';
  ASSERT pg_temp.absence_sum() = abs_before, '6: A REFUSED BOOKING STILL WROTE';

  res := apply_company_absence('FER1000', ARRAY[tuesday], ARRAY[e1, e2, e3]);
  ASSERT res->>'refused' = 'not_bookable', '6: ferie is not bookable';
  ASSERT pg_temp.absence_sum() = abs_before, '6: A NON-BOOKABLE REASON STILL WROTE';

  -- a batch with one bad date among good ones writes none of them
  res := apply_company_absence('FAG1000', ARRAY[tuesday, monday], ARRAY[e1, e2, e3]);
  ASSERT res->>'refused' = 'not_a_working_day', '6: the whole batch is refused';
  ASSERT pg_temp.absence_sum() = abs_before, '6: THE GOOD DATE IN A REFUSED BATCH WAS WRITTEN';

  DELETE FROM holidays WHERE "date" = monday;

  -- ===========================================================================
  -- 7. apply_weekly_staffing still never writes absence
  -- ===========================================================================
  -- The invariant the DISTINCT ON change had to preserve. Absence is read there
  -- to decide how full a week is; it must never be written, whatever the plan
  -- decides.
  abs_before := pg_temp.absence_sum();

  -- a plain booking
  res := apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
           'employee', e1, 'week', wk, 'project', p1, 'days', 2)));
  ASSERT pg_temp.absence_sum() = abs_before, '7: A STAFFING WRITE MODIFIED absence';

  -- one that is partly blocked by absence
  res := apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
           'employee', e2, 'week', wk, 'project', p1, 'days', 5)));
  ASSERT pg_temp.absence_sum() = abs_before, '7: A BLOCKED WRITE MODIFIED absence';

  -- one aimed straight at an absence code, which the planner refuses
  res := apply_weekly_staffing(jsonb_build_array(jsonb_build_object(
           'employee', e1, 'week', wk, 'project', 'FER1000', 'days', 3)));
  ASSERT res->'weeks'->0->'refused'->0->>'reason' = 'absence_not_writable',
         '7: an absence code must be refused, got '
         || COALESCE(res->'weeks'->0->'refused'->0->>'reason', 'null');
  ASSERT pg_temp.absence_sum() = abs_before, '7: A WRITE AIMED AT absence GOT THROUGH';

  -- ===========================================================================
  -- 8. a staffing write stays inside the person-week it names
  -- ===========================================================================
  -- e3 is booked across the same week and is not in any of the payloads above;
  -- their rows must be untouched by all of it.
  ASSERT (SELECT COUNT(*) FROM staffing
           WHERE employee = e3 AND date BETWEEN monday AND (monday + 4)::date) = 5
         AND (SELECT COUNT(DISTINCT percentage) FROM staffing
               WHERE employee = e3 AND date BETWEEN monday AND (monday + 4)::date) = 1
         AND (SELECT MAX(percentage) FROM staffing
               WHERE employee = e3 AND date BETWEEN monday AND (monday + 4)::date) = 60,
         '8: A WRITE FOR SOMEBODY ELSE CHANGED THIS PERSON''S WEEK';

  RAISE NOTICE 'absence write safety: all 8 scenarios passed';
END
$test$;

ROLLBACK;
