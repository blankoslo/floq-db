-- =============================================================================
-- Integration tests for apply_company_absence() and restore_company_absence().
--
--     psql -d floq -f functions/tests/company_absence_test.sql
--
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.
--
-- SAFE TO RUN ANYWHERE. Everything happens inside a transaction that is rolled
-- back at the end, and it borrows existing employees rather than inventing them.
-- The week used is in 2099, so it is certainly empty.
-- =============================================================================

BEGIN;

DO $test$
DECLARE
  e1         integer;
  e2         integer;
  e3         integer;
  wk         text := '2099-10';
  monday     date;
  tuesday    date;
  saturday   date;
  res        jsonb;
  undo       jsonb;
  n          integer;
BEGIN
  SELECT id INTO e1 FROM employees ORDER BY id LIMIT 1;
  SELECT id INTO e2 FROM employees WHERE id <> e1 ORDER BY id LIMIT 1;
  SELECT id INTO e3 FROM employees WHERE id NOT IN (e1, e2) ORDER BY id LIMIT 1;
  ASSERT e3 IS NOT NULL, 'setup: need three employees';

  monday   := to_date(wk || '-1', 'IYYY-IW-ID');
  tuesday  := (monday + 1)::date;
  saturday := (monday + 5)::date;

  DELETE FROM absence WHERE employee_id IN (e1, e2, e3)
    AND date BETWEEN monday AND (monday + 6)::date;
  DELETE FROM holidays WHERE "date" BETWEEN monday AND (monday + 6)::date;

  -- ===========================================================================
  -- 1. the ordinary case: everybody gets the day
  -- ===========================================================================
  res := apply_company_absence('FAG1000', ARRAY[tuesday], ARRAY[e1, e2, e3]);

  ASSERT (res->>'booked')::int = 3, '1: three people booked, got ' || (res->>'booked');
  ASSERT res->>'refused' IS NULL, '1: nothing refused';

  SELECT COUNT(*)::integer INTO n FROM absence
   WHERE reason = 'FAG1000' AND date = tuesday AND employee_id IN (e1, e2, e3);
  ASSERT n = 3, '1: three rows should exist, found ' || n;

  -- ===========================================================================
  -- 2. running it again creates nothing and offers nothing to undo
  -- ===========================================================================
  res := apply_company_absence('FAG1000', ARRAY[tuesday], ARRAY[e1, e2, e3]);

  ASSERT (res->>'booked')::int = 0, '2: nothing new to create';
  ASSERT jsonb_array_length(res->'undo'->'rows') = 0, '2: and nothing to undo';
  ASSERT (SELECT COUNT(*) FROM jsonb_array_elements(res->'people') p
           WHERE p.value->>'status' = 'already_booked') = 3,
         '2: all three reported as already booked';

  -- ===========================================================================
  -- 3. somebody already away that day is skipped and named
  -- ===========================================================================
  DELETE FROM absence WHERE employee_id IN (e1, e2, e3)
    AND date BETWEEN monday AND (monday + 6)::date;
  INSERT INTO absence (employee_id, date, reason) VALUES (e2, tuesday, 'FER1000');

  res := apply_company_absence('FAG1000', ARRAY[tuesday], ARRAY[e1, e2, e3]);

  ASSERT (res->>'booked')::int = 2, '3: two booked, got ' || (res->>'booked');
  ASSERT (SELECT p.value->>'blocked_by' FROM jsonb_array_elements(res->'people') p
           WHERE (p.value->>'employee')::int = e2) = 'FER1000',
         '3: the person on ferie is named with their reason';
  ASSERT NOT EXISTS (SELECT 1 FROM absence
                      WHERE employee_id = e2 AND date = tuesday AND reason = 'FAG1000'),
         '3: AND NO FAGDAG WAS WRITTEN ON TOP OF THE FERIE';

  -- ===========================================================================
  -- 4. undo removes what this batch made, and only that
  -- ===========================================================================
  -- e1 keeps a fagdag they had before the batch; e3 got theirs from it.
  DELETE FROM absence WHERE employee_id IN (e1, e2, e3)
    AND date BETWEEN monday AND (monday + 6)::date;
  INSERT INTO absence (employee_id, date, reason) VALUES (e1, tuesday, 'FAG1000');
  INSERT INTO absence (employee_id, date, reason) VALUES (e2, tuesday, 'FER1000');

  res  := apply_company_absence('FAG1000', ARRAY[tuesday], ARRAY[e1, e2, e3]);
  undo := res->'undo';
  ASSERT jsonb_array_length(undo->'rows') = 1, '4: only e3 was created by this batch';

  res := restore_company_absence(undo);
  ASSERT (res->>'removed')::int = 1, '4: one row removed, got ' || (res->>'removed');

  ASSERT EXISTS (SELECT 1 FROM absence
                  WHERE employee_id = e1 AND date = tuesday AND reason = 'FAG1000'),
         '4: THE FAGDAG THEY ALREADY HAD MUST SURVIVE THE UNDO';
  ASSERT EXISTS (SELECT 1 FROM absence
                  WHERE employee_id = e2 AND date = tuesday AND reason = 'FER1000'),
         '4: AND SO MUST SOMEBODY ELSE''S FERIE';
  ASSERT NOT EXISTS (SELECT 1 FROM absence
                      WHERE employee_id = e3 AND date = tuesday),
         '4: the row this batch created is gone';

  -- undoing twice is not an error, it is a week somebody else has changed
  res := restore_company_absence(undo);
  ASSERT (res->>'removed')::int = 0 AND (res->>'skipped')::int = 1,
         '4: a second undo removes nothing and says so';

  -- ===========================================================================
  -- 5. a holiday and a weekend are refused as values, before anything is written
  -- ===========================================================================
  DELETE FROM absence WHERE employee_id IN (e1, e2, e3)
    AND date BETWEEN monday AND (monday + 6)::date;
  INSERT INTO holidays ("date", "name") VALUES (monday, 'Testfridag');

  res := apply_company_absence('FAG1000', ARRAY[monday], ARRAY[e1, e2, e3]);
  ASSERT res->>'refused' = 'not_a_working_day', '5: a holiday is refused';
  ASSERT (res->>'booked')::int = 0, '5: and nothing was written';

  res := apply_company_absence('FAG1000', ARRAY[saturday], ARRAY[e1, e2, e3]);
  ASSERT res->>'refused' = 'not_a_working_day', '5: so is a Saturday';

  -- one bad date refuses the whole batch rather than half-writing it
  res := apply_company_absence('FAG1000', ARRAY[tuesday, monday], ARRAY[e1, e2, e3]);
  ASSERT res->>'refused' = 'not_a_working_day', '5: the batch is refused as a whole';
  SELECT COUNT(*)::integer INTO n FROM absence
   WHERE reason = 'FAG1000' AND date = tuesday AND employee_id IN (e1, e2, e3);
  ASSERT n = 0, '5: including the good date, found ' || n || ' rows';

  DELETE FROM holidays WHERE "date" = monday;

  -- ===========================================================================
  -- 6. no other absence reason can be booked this way
  -- ===========================================================================
  FOR n IN 1..1 LOOP
    res := apply_company_absence('FER1000', ARRAY[tuesday], ARRAY[e1]);
    ASSERT res->>'refused' = 'not_bookable', '6: ferie is not bookable from the grid';
    ASSERT NOT EXISTS (SELECT 1 FROM absence
                        WHERE employee_id = e1 AND date = tuesday AND reason = 'FER1000'),
           '6: AND NOTHING WAS WRITTEN';

    res := apply_company_absence('ANE1006', ARRAY[tuesday], ARRAY[e1]);
    ASSERT res->>'refused' = 'not_bookable', '6: nor is an ordinary project';
  END LOOP;

  -- ===========================================================================
  -- 7. a dry run answers the same question without writing
  -- ===========================================================================
  DELETE FROM absence WHERE employee_id IN (e1, e2, e3)
    AND date BETWEEN monday AND (monday + 6)::date;
  INSERT INTO absence (employee_id, date, reason) VALUES (e2, tuesday, 'FER1000');

  res := apply_company_absence('FAG1000', ARRAY[tuesday], ARRAY[e1, e2, e3], true);
  ASSERT (res->>'dry_run')::boolean, '7: says it is a dry run';
  ASSERT (res->>'booked')::int = 2, '7: reports what it would book';
  ASSERT jsonb_array_length(res->'undo'->'rows') = 0, '7: with nothing to undo';

  SELECT COUNT(*)::integer INTO n FROM absence WHERE reason = 'FAG1000' AND date = tuesday;
  ASSERT n = 0, '7: AND WROTE NOTHING, found ' || n || ' rows';

  RAISE NOTICE 'apply_company_absence: all 7 scenarios passed';
END
$test$;

ROLLBACK;
