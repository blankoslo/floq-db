-- =============================================================================
-- Tests for plan_weekly_staffing().
--
-- Run against any database that has weekly_staffing_write.sql loaded:
--     psql -d floq -f functions/tests/plan_weekly_staffing_test.sql
--
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.
--
-- plan_weekly_staffing is IMMUTABLE and takes/returns jsonb, so every case here
-- is a single assertion with no fixtures and no tables.
--
-- A normal week holds 5 days of WORK. Absence does not come out of that budget
-- and does not refuse anything — it is recorded on top, and reported back in
-- `absence` as the days of the plan that are not going to happen. So a week can
-- legitimately end up holding 5 booked days plus 2 days of ferie: the plan
-- stays whole, and cancelling the ferie leaves a full week rather than a hole.
-- `hidden_days` is the arithmetic the grid draws with — planned days minus the
-- days left over after absence.
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

-- ---- the `absence` block: what the week really holds -------------------------
CREATE OR REPLACE FUNCTION pg_temp.away_days(plan jsonb) RETURNS integer AS $$
  SELECT (plan->'absence'->>'days')::integer;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.hidden_days(plan jsonb) RETURNS integer AS $$
  SELECT (plan->'absence'->>'hidden_days')::integer;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.away_protected(plan jsonb) RETURNS boolean AS $$
  SELECT (plan->'absence'->>'protected')::boolean;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.away_kinds(plan jsonb) RETURNS jsonb AS $$
  SELECT plan->'absence'->'blocked_by';
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pg_temp.booked_days(plan jsonb) RETURNS integer AS $$
  SELECT COALESCE(SUM((e.value->>'days')::integer), 0)::integer
  FROM jsonb_array_elements(plan->'allocations') e
  WHERE NOT COALESCE((e.value->>'absence')::boolean, false);
$$ LANGUAGE sql;


DO $test$
DECLARE
  p jsonb;
BEGIN
  -- ===========================================================================
  -- Ordinary booking. NOTHING DISPLACES ANYTHING.
  -- ===========================================================================
  -- Every booking is granted what it asked for, capped at the length of the
  -- week and measured against nothing else. Their sum may exceed the week, and
  -- a week whose sum exceeds it is overbooked — a state, not a refusal.

  -- 1. empty week, book 3 days
  p := plan_weekly_staffing(
         '[]'::jsonb,
         '[{"project":"ANE1006","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 3, '1: ANE1006 should be 3';
  ASSERT pg_temp.n_displaced(p) = 0,       '1: nothing should be displaced';
  ASSERT pg_temp.n_refused(p)   = 0,       '1: nothing should be refused';

  -- 2. full on A, book 3 on B -> A KEEPS ALL FIVE and the week is 8 days long.
  --    The old rule shaved A to 2. It could not know which of the two bookings
  --    was the mistake, and it saved its guess.
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":5,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 5, '2: ANE1006 KEEPS ITS WEEK, got '
                                           || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '2: KUN1001 should be 3';
  ASSERT pg_temp.n_refused(p) = 0,         '2: nothing refused — it is overbooked, not refused';
  ASSERT pg_temp.n_displaced(p) = 0,       '2: and nothing displaced';
  ASSERT pg_temp.booked_days(p) = 8,       '2: the week is 8 days long and says so';

  -- 3. a week that is already over (4+3 = 7) is not tidied up by booking into
  --    it. The new day is added and the two incumbents are not touched.
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":4,"absence":false},
           {"project":"KUN1001","days":3,"absence":false}]'::jsonb,
         '[{"project":"ZZZ9999","days":1,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 4, '3: ANE1006 untouched, got ' || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '3: KUN1001 untouched, got ' || pg_temp.days_of(p,'KUN1001');
  ASSERT pg_temp.days_of(p,'ZZZ9999') = 1, '3: ZZZ9999 should be 1';
  ASSERT pg_temp.n_refused(p) = 0,         '3: nothing refused';
  ASSERT pg_temp.n_displaced(p) = 0,       '3: and a booking never repairs a week';

  -- 4. absence sits over a week that the work has already overfilled.
  --    1 sick + 2 A + 2 C, book 3 B. Nothing gives way: the week holds 7 days of
  --    work with a sick day over the top, and 4 of those days will not happen.
  p := plan_weekly_staffing(
         '[{"project":"SYK1001","days":1,"absence":true},
           {"project":"ANE1006","days":2,"absence":false},
           {"project":"ZZZ9999","days":2,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'SYK1001') = 1, '4: sick leave must be untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '4: KUN1001 should be 3';
  ASSERT pg_temp.days_of(p,'ANE1006') = 2, '4: ANE1006 untouched, got ' || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.days_of(p,'ZZZ9999') = 2, '4: ZZZ9999 untouched, got ' || pg_temp.days_of(p,'ZZZ9999');
  ASSERT pg_temp.booked_days(p)  = 7, '4: the work is 7 days in a 5-day week';
  ASSERT pg_temp.hidden_days(p)  = 3, '4: only 4 days are left, so 3 will not happen, got '
                                      || pg_temp.hidden_days(p);
  ASSERT pg_temp.away_protected(p), '4: sykemelding is protected';

  -- 5. a full week booked on top of a full week. NOTHING is drained — this is
  --    the case the old rule was worst at, emptying two projects nobody named.
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":3,"absence":false},
           {"project":"ZZZ9999","days":2,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":5,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 3, '5: ANE1006 NOT drained, got ' || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.days_of(p,'ZZZ9999') = 2, '5: ZZZ9999 NOT drained, got ' || pg_temp.days_of(p,'ZZZ9999');
  ASSERT pg_temp.days_of(p,'KUN1001') = 5, '5: KUN1001 full week';
  ASSERT pg_temp.n_refused(p) = 0,         '5: nothing refused';
  ASSERT pg_temp.booked_days(p) = 10,      '5: ten days, and the grid says so';

  -- ===========================================================================
  -- Absence is never displaced, and never displaces
  -- ===========================================================================
  -- It is not taken from, it is not written, and it does not reduce anybody's
  -- plan. All it does is get reported.

  -- 6. 4 days ferie does NOT stop 3 days being planned. The week keeps the ask;
  --    2 of those days will not happen, and that is what `hidden_days` says.
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":4,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000')  = 4, '6: ferie untouched';
  ASSERT pg_temp.days_of(p,'ANE1006')  = 3, '6: the full ask is recorded, got '
                                            || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.n_refused(p)   = 0,        '6: ferie refuses nothing';
  ASSERT pg_temp.away_days(p)   = 4,        '6: 4 days away';
  ASSERT pg_temp.hidden_days(p) = 2,        '6: only 1 day is free, so 2 are hidden, got '
                                            || pg_temp.hidden_days(p);
  ASSERT pg_temp.away_kinds(p) = '["FER1000"]'::jsonb, '6: should name ferie';
  ASSERT pg_temp.away_protected(p),         '6: ferie is protected';

  -- 7. a full week of ferie still records the plan. Nothing of it will happen,
  --    and cancelling the ferie is what makes it happen.
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":5,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000') = 5, '7: ferie untouched';
  ASSERT pg_temp.days_of(p,'ANE1006') = 3, '7: the plan is still recorded';
  ASSERT pg_temp.n_refused(p)   = 0,       '7: and not refused';
  ASSERT pg_temp.hidden_days(p) = 3,       '7: none of it will happen';

  -- 8. THE CASE THIS ALL EXISTS FOR: 2 ferie + 3 A, book 3 on B.
  --    A and B are 6 days of work in a 5-day week. Neither gives way, and the
  --    ferie takes nothing either — it is reported in hidden_days instead. Under
  --    the oldest rule the ferie pushed A all the way to 0 and saved it, so
  --    cancelling the ferie left A on nothing.
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":2,"absence":true},
           {"project":"ANE1006","days":3,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000') = 2, '8: ferie untouched';
  ASSERT pg_temp.days_of(p,'ANE1006') = 3, '8: ANE1006 keeps all 3, got '
                                           || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '8: KUN1001 should be 3';
  ASSERT pg_temp.booked_days(p) = 6,       '8: 6 days of work in the week';
  ASSERT pg_temp.n_refused(p)   = 0,       '8: nothing refused';
  ASSERT pg_temp.n_displaced(p) = 0,       '8: and nothing displaced';
  ASSERT pg_temp.hidden_days(p) = 3,       '8: only 3 days are left, so 3 will not happen, got '
                                           || pg_temp.hidden_days(p);

  -- 9. same again but booking 2 instead of 3 -> the work fits, so A keeps all 3
  --    and nothing is displaced at all
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":2,"absence":true},
           {"project":"ANE1006","days":3,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":2,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000') = 2, '9: ferie untouched';
  ASSERT pg_temp.days_of(p,'ANE1006') = 3, '9: ANE1006 keeps all 3, got '
                                           || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.days_of(p,'KUN1001') = 2, '9: KUN1001 should be 2';
  ASSERT pg_temp.n_displaced(p) = 0,       '9: NOTHING should be displaced';
  ASSERT pg_temp.hidden_days(p) = 2,       '9: 2 planned days are ferie';

  -- 10. absence present and the work exactly fills the week: nothing moves, and
  --     the total legitimately exceeds capacity because the ferie is on top
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":2,"absence":true},
           {"project":"ANE1006","days":2,"absence":false},
           {"project":"ZZZ9999","days":2,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":1,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000') = 2, '10: ferie untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 1, '10: KUN1001 booked';
  ASSERT pg_temp.days_of(p,'ANE1006') = 2, '10: ANE1006 keeps its days';
  ASSERT pg_temp.days_of(p,'ZZZ9999') = 2, '10: ZZZ9999 keeps its days';
  ASSERT pg_temp.booked_days(p)  = 5,      '10: the work fits exactly';
  ASSERT pg_temp.n_displaced(p)  = 0,      '10: so nothing is displaced';
  ASSERT pg_temp.hidden_days(p)  = 2,      '10: 2 of the 5 are ferie';

  -- 11. unprotected absence is reported as such, and refuses nothing either
  p := plan_weekly_staffing(
         '[{"project":"AVS","days":2,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":4,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'AVS')     = 2, '11: avspasering untouched';
  ASSERT pg_temp.days_of(p,'ANE1006') = 4, '11: all 4 days recorded';
  ASSERT pg_temp.n_refused(p)   = 0,       '11: avspasering refuses nothing';
  ASSERT pg_temp.hidden_days(p) = 1,       '11: 3 days are free, so 1 is hidden';
  ASSERT NOT pg_temp.away_protected(p),    '11: avspasering is not protected';

  -- 12. protected wins the flag when both kinds are present, so a caller can
  --     still tell "she is away" from "she might yet come"
  p := plan_weekly_staffing(
         '[{"project":"AVS","days":1,"absence":true},
           {"project":"FER1000","days":3,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.away_protected(p), '12: protected absence should win the flag';
  ASSERT pg_temp.away_days(p)   = 4, '12: 4 days away between the two kinds';
  ASSERT pg_temp.hidden_days(p) = 2, '12: 1 day free, so 2 of the 3 are hidden';
  ASSERT pg_temp.away_kinds(p) @> '["AVS"]'::jsonb
     AND pg_temp.away_kinds(p) @> '["FER1000"]'::jsonb, '12: both kinds named';

  -- ===========================================================================
  -- Fagutvikling, specifically (it is absence in the database, and the old app
  -- left it out of its hardcoded list)
  -- ===========================================================================

  -- 13. fits alongside with nothing hidden: 2 fagdager plus 3 days of work is
  --     exactly a week, so the whole plan happens
  p := plan_weekly_staffing(
         '[{"project":"FAG1000","days":2,"absence":true}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FAG1000') = 2, '13: fagutvikling untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '13: fits exactly';
  ASSERT pg_temp.n_refused(p)   = 0,       '13: nothing refused';
  ASSERT pg_temp.hidden_days(p) = 0,       '13: and nothing hidden';

  -- 14. the work fits the week, so the fagutvikling costs KUN1001 nothing
  p := plan_weekly_staffing(
         '[{"project":"FAG1000","days":2,"absence":true},
           {"project":"KUN1001","days":3,"absence":false}]'::jsonb,
         '[{"project":"ANE1006","days":2,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FAG1000') = 2, '14: fagutvikling untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '14: KUN1001 keeps all 3, got '
                                           || pg_temp.days_of(p,'KUN1001');
  ASSERT pg_temp.days_of(p,'ANE1006') = 2, '14: ANE1006 booked';
  ASSERT pg_temp.n_displaced(p) = 0,       '14: nothing displaced';
  ASSERT pg_temp.hidden_days(p) = 2,       '14: 2 of the 5 planned days are fagdager';

  -- 15. a full week of fagutvikling refuses nothing either — the booking is
  --     recorded and reported as entirely hidden
  p := plan_weekly_staffing(
         '[{"project":"FAG1000","days":5,"absence":true}]'::jsonb,
         '[{"project":"KUN1001","days":3,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FAG1000') = 5, '15: fagutvikling untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 3, '15: the plan is recorded';
  ASSERT pg_temp.n_refused(p)   = 0,       '15: nothing refused';
  ASSERT pg_temp.hidden_days(p) = 3,       '15: none of it happens';
  ASSERT NOT pg_temp.away_protected(p),    '15: fagutvikling is not protected';

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

  -- 19. a caller passing a shorter week
  --     The planner takes capacity as an argument and asks no questions about
  --     it. apply_weekly_staffing() now always passes 5 — a holiday does not
  --     shorten a plan — but the rule itself still holds for any capacity.
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
  ASSERT pg_temp.days_of(p,'ZZZ9999') = 5, '24: the incumbent gives way to NEITHER, got '
                                           || pg_temp.days_of(p,'ZZZ9999');
  ASSERT pg_temp.booked_days(p) = 9,       '24: two targets in one call do not share the week either';

  -- ===========================================================================
  -- The plan survives the absence
  -- ===========================================================================
  -- The reason for all of the above. Absence arrives, absence leaves, and what
  -- somebody planned is still there either side of it.

  -- 25. absence appears on a full week and NOTHING is rewritten. There are no
  --     targets at all here, which is the state a dry run reports for a week
  --     somebody is merely looking at.
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":2,"absence":true},
           {"project":"ANE1006","days":5,"absence":false}]'::jsonb,
         '[]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 5, '25: THE PLAN MUST SURVIVE, got '
                                           || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.n_displaced(p) = 0,       '25: and nothing displaced';
  ASSERT pg_temp.hidden_days(p) = 2,       '25: 2 of the 5 days are ferie';

  -- 26. Knut staffs a full week into one that is already 2 days absent. All 5
  --     are recorded, because 5 is what he asked for and it is the only version
  --     that is still right if she cancels those 2 days.
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":2,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":5,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 5, '26: the full ask is recorded, got '
                                           || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.n_refused(p)   = 0,       '26: and not clipped to 3';
  ASSERT pg_temp.away_days(p)   = 2,       '26: 2 days away';
  ASSERT pg_temp.hidden_days(p) = 2,       '26: so 2 of the 5 will not happen';

  -- 27. ...and the absence being cancelled needs no repair: the same plan with
  --     no absence in it is a full week, with nothing hidden
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":5,"absence":false}]'::jsonb,
         '[]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 5, '27: a full week, as planned';
  ASSERT pg_temp.hidden_days(p) = 0,       '27: nothing hidden any more';
  ASSERT pg_temp.away_days(p)   = 0,       '27: nobody is away';

  -- 28. what absence still does NOT do is buy extra room. A week is 5 days of
  --     work whoever is away, so 6 is still one too many.
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":2,"absence":true}]'::jsonb,
         '[{"project":"ANE1006","days":6,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006')      = 5, '28: capped at a week';
  ASSERT pg_temp.shortfall_of(p,'ANE1006') = 1, '28: 1 over';
  ASSERT pg_temp.reason_of(p,'ANE1006') = 'exceeds_week_capacity',
         '28: the length of the week is the reason, not the ferie, got '
         || COALESCE(pg_temp.reason_of(p,'ANE1006'), 'null');
  ASSERT pg_temp.blocked_by(p,'ANE1006') = '[]'::jsonb,
         '28: a refusal must not name absence as its cause';

  -- ===========================================================================
  -- Overbooking: the sum of a week is allowed past the week
  --
  -- These are the cases the rule was changed for. INT1000 is nonbillable and
  -- ANE1006/KUN1001 are not, and that makes NO difference to any of them —
  -- `billable` is not an input any more.
  -- ===========================================================================

  -- 29. THE RULE. Two client projects, a full week each. 37,5 t + 37,5 t is
  --     75 t, and the grid prints 75.
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":5,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":5,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 5, '29: ANE1006 keeps its week, got '
                                           || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.days_of(p,'KUN1001') = 5, '29: KUN1001 gets its week too';
  ASSERT pg_temp.booked_days(p) = 10,      '29: ten days';
  ASSERT pg_temp.n_displaced(p) = 0,       '29: nothing displaced';
  ASSERT pg_temp.n_refused(p)   = 0,       '29: nothing refused';

  -- 30. an internal code behaves identically — one rule, not two budgets
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":5,"absence":false}]'::jsonb,
         '[{"project":"INT1000","days":1,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006') = 5, '30: ANE1006 untouched';
  ASSERT pg_temp.days_of(p,'INT1000') = 1, '30: the internal day is granted';
  ASSERT pg_temp.booked_days(p) = 6,       '30: 6 of 5';

  -- 31. and in the other order, which the two-budget version made asymmetric
  p := plan_weekly_staffing(
         '[{"project":"INT1000","days":5,"absence":false}]'::jsonb,
         '[{"project":"ANE1006","days":5,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'INT1000') = 5, '31: INT1000 untouched';
  ASSERT pg_temp.days_of(p,'ANE1006') = 5, '31: ANE1006 gets its full week';

  -- 32. ONE PROJECT IS STILL CAPPED AT THE WEEK. This is the only thing
  --     `exceeds_week_capacity` means now: not "the week is full", but "you
  --     asked for more days than a week has".
  p := plan_weekly_staffing(
         '[{"project":"KUN1001","days":5,"absence":false}]'::jsonb,
         '[{"project":"ANE1006","days":7,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'ANE1006')      = 5, '32: clipped to a week, got '
                                                || pg_temp.days_of(p,'ANE1006');
  ASSERT pg_temp.shortfall_of(p,'ANE1006') = 2, '32: 2 over';
  ASSERT pg_temp.reason_of(p,'ANE1006') = 'exceeds_week_capacity',
         '32: the length of the week is the reason, got '
         || COALESCE(pg_temp.reason_of(p,'ANE1006'), 'null');
  ASSERT pg_temp.days_of(p,'KUN1001') = 5, '32: and the clipping costs KUN1001 nothing';

  -- 33. the week being full is NOT a refusal. Same shape as 32, asked for 5.
  p := plan_weekly_staffing(
         '[{"project":"KUN1001","days":5,"absence":false}]'::jsonb,
         '[{"project":"ANE1006","days":5,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.n_refused(p) = 0, '33: a full week refuses nothing';

  -- 34. absence still takes days off what will HAPPEN, and still takes none off
  --     what is stored — the one rule that did not change.
  p := plan_weekly_staffing(
         '[{"project":"FER1000","days":3,"absence":true},
           {"project":"ANE1006","days":5,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":5,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.days_of(p,'FER1000') = 3, '34: ferie untouched';
  ASSERT pg_temp.days_of(p,'ANE1006') = 5, '34: ANE1006 untouched';
  ASSERT pg_temp.days_of(p,'KUN1001') = 5, '34: KUN1001 granted in full';
  ASSERT pg_temp.n_displaced(p) = 0,       '34: absence displaces nothing, and neither does work';
  ASSERT pg_temp.hidden_days(p) = 8,       '34: 10 days planned, 2 left, so 8 will not happen, got '
                                           || pg_temp.hidden_days(p);

  -- 35. `displaced` is now always empty, whatever is thrown at it. The field
  --     stays so an older client keeps rendering; this is what holds it empty.
  p := plan_weekly_staffing(
         '[{"project":"ANE1006","days":5,"absence":false},
           {"project":"ZZZ9999","days":5,"absence":false}]'::jsonb,
         '[{"project":"KUN1001","days":5,"absence":false}]'::jsonb, 5);
  ASSERT pg_temp.n_displaced(p) = 0,  '35: displaced must always be empty';
  ASSERT pg_temp.booked_days(p) = 15, '35: fifteen days, all of them kept';

  RAISE NOTICE 'plan_weekly_staffing: all 35 cases passed';
END
$test$;
