-- =============================================================================
-- Tests for plan_weekly_staffing().
--
-- Run against any database that has weekly_staffing_write.sql loaded:
--     psql -d floq -f functions/tests/plan_weekly_staffing_test.sql
--
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.
--
-- plan_weekly_staffing is IMMUTABLE and takes/returns jsonb, so every case here
-- is a single assertion with no fixtures and no tables. A normal week holds 5
-- days; absence takes days off the top and what is left is all that can hold
-- work.
--
-- Project codes are chosen so alphabetical order is obvious:
--   ANE1006 < KUN1001 < ZZZ9999.  Ties in "shave the largest" break by code
--   ascending, so ANE1006 gives way before KUN1001 when both are equal.
-- =============================================================================

-- ---- helpers (session-local, vanish on disconnect) --------------------------
CREATE OR REPLACE FUNCTION pg_temp.days_of(plan jsonb, proj text) RETURNS integer AS $$
  SELECT COALESCE((SELECT (e.value->>'days')::integer
                   FROM jsonb_array_elements(plan->'allocations') e
                   WHERE e.value->>'project' = proj), -1);
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.reason_of(plan jsonb, proj text) RETURNS text AS $$
  SELECT (SELECT e.value->>'reason'
          FROM jsonb_array_elements(plan->'refused') e
          WHERE e.value->>'project' = proj);
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.shortfall_of(plan jsonb, proj text) RETURNS integer AS $$
  SELECT COALESCE((SELECT (e.value->>'shortfall_days')::integer
                   FROM jsonb_array_elements(plan->'refused') e
                   WHERE e.value->>'project' = proj), 0);
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.granted_of(plan jsonb, proj text) RETURNS integer AS $$
  SELECT COALESCE((SELECT (e.value->>'granted_days')::integer
                   FROM jsonb_array_elements(plan->'refused') e
                   WHERE e.value->>'project' = proj), -1);
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.n_refused(plan jsonb) RETURNS integer AS $$
  SELECT jsonb_array_length(plan->'refused');
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.n_displaced(plan jsonb) RETURNS integer AS $$
  SELECT jsonb_array_length(plan->'displaced');
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.blocked_by(plan jsonb, proj text) RETURNS jsonb AS $$
  SELECT (SELECT e.value->'blocked_by'
          FROM jsonb_array_elements(plan->'refused') e
          WHERE e.value->>'project' = proj);
$$ LANGUAGE sql;


DO $test$
DECLARE
  p jsonb;
BEGIN
  -- ===========================================================================
  -- Ordinary booking and displacement
  -- ===========================================================================

  -- 1. empty week, book 3 days
  p := plan_weekly_staffing(
         '[]'::jsonb,
         '[{"project":"ANE1006","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 3, '1: ANE1006 should be 3';
  ASSERT pg_temp.n_displaced(p) = 0,       '1: nothing should be displaced';
  ASSERT pg_temp.n_refused(p)   = 0,       '1: nothing should be refused';

  -- 2. full on A, book 3 on B -> A gives up exactly 3
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":5,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 2, '2: ANE1006 should drop to 2';
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '2: KUN1001 should be 3';
  ASSERT pg_temp.n_refused(p) = 0,         '2: nothing refused';
  ASSERT pg_temp.n_displaced(p) = 1,       '2: exactly one project displaced';

  -- 3. week that is already overbooked from historical data (4+3 = 7 > 5).
  --    Booking 1 more shaves one day at a time off the current largest, which
  --    evens the two out rather than draining one: 4,3 -> 3,3 -> 2,3 -> 2,2.
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":4,"absence":false},
           {"project":"KUN1001","days":3,"absence":false}]'::jsonb,
         '[{"project":"ZZZ9999","days":1,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 2, '3: ANE1006 should be 2, got '   || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.days_of(p,'KUN1001') = 2, '3: KUN1001 should be 2, got '   || pg_temp.days_of(p,'KUN1001');
  ASSERT pg_temp.days_of(p,'ZZZ9999') = 1, '3: ZZZ9999 should be 1';
  ASSERT pg_temp.n_refused(p) = 0,         '3: nothing refused';

  -- 4. shaving is one day at a time off the largest, tie-broken by code.
  --    1 sick + 2 A + 2 C, book 3 B: A->1, C->1, A->0.
  p := plan_weekly_staffing(
         '[{"project":"SYK1001","days":1,"absence":true},
           {"project":"ANE1006","days":2,"absence":false},
           {"project":"ZZZ9999","days":2,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'SYK1001') = 1, '4: sick leave must be untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '4: KUN1001 should be 3';
  ASSERT pg_temp.days_of(p,'ANE1006') = 0, '4: ANE1006 should be 0, got ' || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.days_of(p,'ZZZ9999') = 1, '4: ZZZ9999 should be 1, got ' || pg_temp.days_of(p,'ZZZ9999');

  -- 5. draining everything movable
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":3,"absence":false},
           {"project":"ZZZ9999","days":2,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":5,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 0, '5: ANE1006 drained';
  ASSERT pg_temp.days_of(p,'ZZZ9999') = 0, '5: ZZZ9999 drained';
  ASSERT pg_temp.days_of(p,'KUN1001') = 5, '5: KUN1001 full week';
  ASSERT pg_temp.n_refused(p) = 0,         '5: nothing refused';

  -- ===========================================================================
  -- Absence is never displaced
  -- ===========================================================================

  -- 6. 4 days ferie leaves room for 1
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":4,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000')    = 4, '6: ferie untouched';
  ASSERT pg_temp.days_of(p,'ANE1006')    = 1, '6: only 1 day fits';
  ASSERT pg_temp.shortfall_of(p,'ANE1006') = 2, '6: 2 days should not fit';
  ASSERT pg_temp.reason_of(p,'ANE1006') = 'blocked_by_protected_absence', '6: wrong reason';
  ASSERT pg_temp.blocked_by(p,'ANE1006') = '["FER1000"]'::jsonb, '6: should name ferie';

  -- 7. a full week of ferie takes nothing at all
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":5,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000')      = 5, '7: ferie untouched';
  ASSERT pg_temp.days_of(p,'ANE1006')      = 0, '7: nothing booked';
  ASSERT pg_temp.shortfall_of(p,'ANE1006') = 3, '7: all 3 days refused';

  -- 8. THE CASE FROM THE PLAN: 2 ferie + 3 A, book 3 on B.
  --    Ferie takes 2 of the 5, so only 3 days can hold work and A is sitting in
  --    all three of them. Booking 3 of B leaves A with nothing. A drops to 0
  --    because A only had 3 to begin with, not because it lost 3 from more.
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":2,"absence":true},
           {"project":"ANE1006","days":3,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000') = 2, '8: ferie untouched';
  ASSERT pg_temp.days_of(p,'ANE1006') = 0, '8: ANE1006 should be 0';
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '8: KUN1001 should be 3';
  ASSERT pg_temp.n_refused(p) = 0,         '8: it fits, so nothing is refused';

  -- 9. same again but booking 2 instead of 3 -> A keeps 1
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":2,"absence":true},
           {"project":"ANE1006","days":3,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":2,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000') = 2, '9: ferie untouched';
  ASSERT pg_temp.days_of(p,'ANE1006') = 1, '9: ANE1006 should keep 1';
  ASSERT pg_temp.days_of(p,'KUN1001') = 2, '9: KUN1001 should be 2';

  -- 10. historical overbooking WITH absence present: reduce what is movable,
  --     never go negative, never touch the ferie
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":2,"absence":true},
           {"project":"ANE1006","days":2,"absence":false},
           {"project":"ZZZ9999","days":2,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":1,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000') = 2, '10: ferie untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 1, '10: KUN1001 booked';
  ASSERT pg_temp.days_of(p,'ANE1006') >= 0 AND pg_temp.days_of(p,'ZZZ9999') >= 0,
         '10: never negative';
  ASSERT pg_temp.days_of(p,'FER1000') + pg_temp.days_of(p,'ANE1006')
       + pg_temp.days_of(p,'ZZZ9999') + pg_temp.days_of(p,'KUN1001') = 5,
         '10: week must end up at exactly capacity';

  -- 11. unprotected absence gets the softer reason, and is still not displaced
  p := plan_weekly_staffing(
         '[{"project":"AVS","days":2,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":4,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'AVS')       = 2, '11: avspasering untouched';
  ASSERT pg_temp.days_of(p,'ANE1006')   = 3, '11: 3 of 4 days fit';
  ASSERT pg_temp.reason_of(p,'ANE1006') = 'blocked_by_absence', '11: should be the soft reason';

  -- 12. protected wins when both kinds are present
  p := plan_weekly_staffing(
         '[{"project":"AVS","days":1,"absence":true},
           {"project":"FER1000","days":3,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.reason_of(p,'ANE1006') = 'blocked_by_protected_absence',
         '12: protected absence should win the message';

  -- ===========================================================================
  -- Fagutvikling, specifically (it is absence in the database, and the old app
  -- left it out of its hardcoded list)
  -- ===========================================================================

  -- 13. fits alongside
  p := plan_weekly_staffing(
         '[{"project":"FAG1000","days":2,"absence":true}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FAG1000') = 2, '13: fagutvikling untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '13: fits exactly';
  ASSERT pg_temp.n_refused(p) = 0,         '13: nothing refused';

  -- 14. displaces the project, not the fagutvikling
  p := plan_weekly_staffing(
         '[{"project":"FAG1000","days":2,"absence":true},
           {"project":"KUN1001","days":3,"absence":false}]'::jsonb,
         '[{"project":"ANE1006","days":2,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FAG1000') = 2, '14: fagutvikling untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 1, '14: KUN1001 gives up 2';
  ASSERT pg_temp.days_of(p,'ANE1006') = 2, '14: ANE1006 booked';

  -- 15. a full week of fagutvikling refuses everything, softly
  p := plan_weekly_staffing(
         '[{"project":"FAG1000","days":5,"absence":true}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FAG1000')      = 5, '15: fagutvikling untouched';
  ASSERT pg_temp.days_of(p,'KUN1001')      = 0, '15: nothing booked';
  ASSERT pg_temp.shortfall_of(p,'KUN1001') = 3, '15: all 3 refused';
  ASSERT pg_temp.reason_of(p,'KUN1001')    = 'blocked_by_absence', '15: soft reason';

  -- 16. booking fagutvikling itself from the grid is refused, not thrown --
  --     so the rest of a batch still saves
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":2,"absence":false}]'::jsonb,
         '[{"project":"FAG1000","days":3,"absence":true}]'::jsonb, 5);
  ASSERT pg_temp.reason_of(p,'FAG1000') = 'absence_not_writable', '16: wrong reason';
  ASSERT pg_temp.granted_of(p,'FAG1000') = 0, '16: nothing granted';
  ASSERT pg_temp.days_of(p,'ANE1006')   = 2, '16: the rest of the week is untouched';

  -- 17. same for ferie
  p := plan_weekly_staffing(
         '[]'::jsonb,
         '[{"project":"FER1000","days":3,"absence":true}]'::jsonb, 5);
  ASSERT pg_temp.reason_of(p,'FER1000') = 'absence_not_writable', '17: wrong reason';

  -- ===========================================================================
  -- Capacity edges
  -- ===========================================================================

  -- 18. more than a week
  p := plan_weekly_staffing(
         '[]'::jsonb,
         '[{"project":"ANE1006","days":6,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006')      = 5, '18: capped at 5';
  ASSERT pg_temp.shortfall_of(p,'ANE1006') = 1, '18: 1 over';
  ASSERT pg_temp.reason_of(p,'ANE1006')    = 'exceeds_week_capacity', '18: wrong reason';

  -- 19. holiday week has only 4 working days
  p := plan_weekly_staffing(
         '[]'::jsonb,
         '[{"project":"ANE1006","days":5,"absence":false}]'::jsonb, 4);
  ASSERT pg_temp.days_of(p,'ANE1006')      = 4, '19: capped at 4';
  ASSERT pg_temp.shortfall_of(p,'ANE1006') = 1, '19: 1 over';

  -- 20. a week with no working days at all
  p := plan_weekly_staffing(
         '[]'::jsonb,
         '[{"project":"ANE1006","days":3,"absence":false}]'::jsonb, 0);
  ASSERT pg_temp.days_of(p,'ANE1006')   = 0, '20: nothing booked';
  ASSERT pg_temp.reason_of(p,'ANE1006') = 'no_workable_days', '20: wrong reason';

  -- ===========================================================================
  -- Clearing, self-targeting, idempotence
  -- ===========================================================================

  -- 21. booking 0 clears that project and leaves the rest alone
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":3,"absence":false},
           {"project":"KUN1001","days":2,"absence":false}]'::jsonb,
         '[{"project":"ANE1006","days":0,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 0, '21: cleared';
  ASSERT pg_temp.days_of(p,'KUN1001') = 2, '21: the other project is untouched';
  ASSERT pg_temp.n_refused(p) = 0,         '21: clearing is never refused';

  -- 22. raising a project that is already there: its own days are not treated
  --     as something to displace
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":2,"absence":false}]'::jsonb,
         '[{"project":"ANE1006","days":4,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 4, '22: should reach 4';
  ASSERT pg_temp.n_refused(p) = 0,         '22: nothing refused';
  ASSERT pg_temp.n_displaced(p) = 0,       '22: the target is not "displaced"';

  -- 23. applying the same thing twice changes nothing the second time
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":2,"absence":false},
           {"project":"KUN1001","days":3,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 2, '23: unchanged';
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '23: unchanged';
  ASSERT pg_temp.n_displaced(p) = 0,       '23: nothing displaced on a repeat';

  -- 24. two projects booked in one call
  p := plan_weekly_staffing(
         '[{"project":"ZZZ9999","days":5,"absence":false}]'::jsonb,
         '[{"project":"ANE1006","days":2,"absence":false},
           {"project":"KUN1001","days":2,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 2, '24: first target booked';
  ASSERT pg_temp.days_of(p,'KUN1001') = 2, '24: second target booked';
  ASSERT pg_temp.days_of(p,'ZZZ9999') = 1, '24: the incumbent gives way to both';

  RAISE NOTICE 'plan_weekly_staffing: all 24 cases passed';
END
$test$;
