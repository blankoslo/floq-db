-- =============================================================================
-- Weekly staffing capacity — the company rule, in one place.
--
-- A person's week holds at most `capacity_days` working days. Two separate
-- questions follow from that, and keeping them apart is the whole point:
--
--   Granting      How many days the booking being made now gets. Bounded by the
--                 length of the week, and by anything else booked in the same
--                 call. NOT by absence.
--
--   Displacement  How many days the bookings ALREADY in the week have to give
--                 up. Only a new booking causes this — largest allocation
--                 first, one day at a time. NOT absence.
--
-- Absence appears in neither. It is read here, to report how much of the plan it
-- covers, and it is never written and never taken from: it lives in a different
-- table and is only ever changed in the absence calendar.
--
-- So `staffing` holds what somebody *planned*, and with absence present the
-- non-absence allocations plus the absence can add up to more than
-- `capacity_days`. That is the point, not a defect. 5 booked days plus 2 days of
-- ferie is a plan the ferie has overtaken; the week is still only going to
-- happen 3 days' worth, and every reader works that out for itself.
-- displaceByAbsence.ts in floq-staffing-v3 is the display rule, and it shaves in
-- this same largest-first order.
--
-- Why not write the smaller number down instead?
--
-- Anna is booked 5 days on ANE1006 and then takes 2 days off. Shave ANE1006 to 3
-- in the table, and when she cancels those days she is left on 3: two days of
-- somebody's plan are gone and nothing anywhere remembers they existed. Leave it
-- at 5 and cancelling the absence gives her a full week back by itself. The
-- alternative needs machinery this does not have — absence is inserted and
-- deleted by the fraværskalender, which knows nothing about staffing, so "shrink
-- it now, put it back later" would mean a trigger on `absence` and a record of
-- what was taken from whom.
--
-- The same argument covers granting. If Knut staffs Anna 5 days in a week she is
-- already away 2 of, storing 3 throws away what he asked for; storing 5 keeps it,
-- and `absence.hidden_days` in the result tells him 2 of those days are not going
-- to happen. He is informed either way — but only one of them survives Anna
-- changing her mind.
--
-- The second reason is blast radius. Booking one day of BLA1000 into Anna's week
-- used to take three days off ANE1006 — a project the caller never named, picked
-- by a largest-first tie-break, and saved for good.
--
-- Split into a pure planner and a thin applier on purpose:
--
--   plan_weekly_staffing()   IMMUTABLE, touches no tables. The rule itself.
--                            Unit-testable with no fixtures, and callable by
--                            floq-kpi / reports-api for what-if analysis.
--   apply_weekly_staffing()  Reads real state, asks the planner, writes the
--                            answer — all inside ONE transaction, so a bulk
--                            change can never be left half-done.
--
-- Refusals are returned VALUES, not exceptions. That is what allows
-- "38 saved / 4 refused" and all-or-nothing durability at the same time.
--
-- -----------------------------------------------------------------------------
-- MAINTENANCE WARNING
--
-- functions/deploy.sh re-runs every functions/*.sql alphabetically on every
-- deploy, so everything here must stay CREATE OR REPLACE.
--
-- CHANGING ANY ARGUMENT LIST BELOW REQUIRES UN-COMMENTING THE MATCHING DROP
-- FIRST. Postgres will otherwise create a second overload and PostgREST starts
-- answering PGRST203 "ambiguous". This repo already has that hazard:
-- remove_staffing exists as both (int,text,int,int,int) in staffing_functions.sql
-- and (int,text,date,date) in staffing_in_periods.sql.
--
-- DROP FUNCTION IF EXISTS public.plan_weekly_staffing(jsonb, jsonb, integer);
-- DROP FUNCTION IF EXISTS public.apply_weekly_staffing(jsonb, boolean);
-- DROP FUNCTION IF EXISTS public.restore_weekly_staffing(jsonb);
-- DROP FUNCTION IF EXISTS public.overbooked_weeks(date, date);
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Which absence gets the firm refusal message.
--
-- ALL absence is immovable — this only picks the wording. Ferie, sykemelding
-- and permisjon cannot be moved at all ("kan ikke overskrives"); foreldreperm,
-- fagutvikling and avspasering are things a person can reschedule, so they get
-- "fjern fraværet i fraværskalenderen først".
--
-- Deliberately NOT the same set as is_absence_reason() in absence_reasons_view.sql.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_protected_absence(reason text)
        RETURNS boolean AS
$$
BEGIN
  RETURN (    reason = 'FER1000'  -- Ferie
           OR reason = 'SYK1000'  -- Egenmelding
           OR reason = 'SYK1001'  -- Sykemelding
           OR reason = 'SYK1002'  -- Sykt barn
           OR reason = 'PER1000'  -- Permisjon med lønn
           OR reason = 'PER1001'  -- Permisjon uten lønn
         );
END
$$ LANGUAGE plpgsql IMMUTABLE;


-- -----------------------------------------------------------------------------
-- The rule, as a pure function.
--
--   in_current  [{"project":"ANE1006","days":3,"absence":false}, ...]
--   in_targets  [{"project":"ANE1006","days":2,"absence":false}, ...]
--
-- Callers MUST set "absence" themselves (apply_weekly_staffing does, via
-- is_absence_reason). It is not looked up here, because doing so would mean
-- reading a table and this function would stop being pure — which is the whole
-- point of it.
--
-- Returns:
--   { "capacity_days": 5,
--     "allocations": [{"project":"X","days":2,"absence":false}, ...],
--     "displaced":   [{"project":"Y","days_before":4,"days_after":2}, ...],
--     "refused":     [{"project":"X","requested_days":6,"granted_days":5,
--                      "shortfall_days":1,"reason":"...","blocked_by":[]}],
--                     -- blocked_by is now always empty; see below
--     "absence":     {"days":2,"hidden_days":2,"blocked_by":["FER1000"],
--                     "protected":true} }
--
-- `allocations` is the complete intended end state for the week, including
-- entries at 0 days so the caller knows to delete them, and including absence
-- (flagged) so a UI can draw the whole week. The caller must not write absence.
--
-- The non-absence entries sum to at most `capacity_days`. The whole list can
-- exceed it, because absence sits on top of the plan rather than being taken out
-- of it — see the two halves of the rule at the top of this file.
--
-- `displaced` therefore only ever reports work that gave way to *other work*. A
-- booking the absence covers is not displaced: it still says what was planned,
-- and it is intact the moment the absence goes away.
--
-- `absence` is how the caller finds out anyway, and is the only reason absence is
-- read here at all:
--   days         working days of the week the person is away
--   hidden_days  planned days those absence days cover — what will not happen
--   blocked_by   which kinds, so a message can name them
--   protected    true if any of them is ferie, sykdom or permisjon, which is
--                the difference between "she is away" and "she might yet come"
--
-- `reason` is a closed set:
--   exceeds_week_capacity | absence_not_writable | no_workable_days
--
-- blocked_by_protected_absence and blocked_by_absence are retired: absence no
-- longer refuses anything, it is reported in `absence` instead. The values stay
-- named here because callers still have the labels, and nothing is gained by
-- making an old client fail to render a reason it will never receive.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.plan_weekly_staffing(
    in_current       jsonb,
    in_targets       jsonb,
    in_capacity_days integer DEFAULT 5
) RETURNS jsonb
AS $$
DECLARE
    cap           integer   := GREATEST(COALESCE(in_capacity_days, 0), 0);
    n             integer   := 0;
    proj          text[]    := ARRAY[]::text[];
    days          integer[] := ARRAY[]::integer[];
    is_abs        boolean[] := ARRAY[]::boolean[];
    locked        boolean[] := ARRAY[]::boolean[];
    was_target    boolean[] := ARRAY[]::boolean[];
    before_days   integer[] := ARRAY[]::integer[];
    blocked_by    text[]    := ARRAY[]::text[];
    has_protected boolean   := false;
    absence_days  integer   := 0;
    rec           jsonb;
    i             integer;
    t_proj        text;
    t_req         integer;
    t_idx         integer;
    locked_sum    integer;
    room          integer;
    granted       integer;
    reason        text;
    total         integer;
    over          integer;
    big_idx       integer;
    big_val       integer;
    hidden        integer   := 0;
    allocations   jsonb     := '[]'::jsonb;
    displaced     jsonb     := '[]'::jsonb;
    refused       jsonb     := '[]'::jsonb;
BEGIN
    -- ---- load the week as it stands, merged by project, sorted for determinism
    FOR rec IN
        SELECT jsonb_build_object('project', x.project,
                                  'days',    SUM(x.days),
                                  'absence', bool_or(x.absence))
        FROM (
            SELECT e.value->>'project'                                   AS project,
                   GREATEST(COALESCE((e.value->>'days')::integer, 0), 0) AS days,
                   COALESCE((e.value->>'absence')::boolean, false)       AS absence
            FROM jsonb_array_elements(COALESCE(in_current, '[]'::jsonb)) e
            WHERE e.value->>'project' IS NOT NULL
        ) x
        GROUP BY x.project
        ORDER BY x.project
    LOOP
        n          := n + 1;
        proj       := array_append(proj,       rec->>'project');
        days       := array_append(days,       (rec->>'days')::integer);
        is_abs     := array_append(is_abs,     (rec->>'absence')::boolean);
        was_target := array_append(was_target, false);
    END LOOP;

    before_days := days;

    -- absence is locked from the start and counts against the week
    FOR i IN 1..n LOOP
        locked := array_append(locked, is_abs[i]);
        IF is_abs[i] THEN
            absence_days := absence_days + days[i];
            blocked_by   := array_append(blocked_by, proj[i]);
            IF is_protected_absence(proj[i]) THEN
                has_protected := true;
            END IF;
        END IF;
    END LOOP;

    -- ---- apply each target in turn -----------------------------------------
    FOR rec IN
        SELECT jsonb_build_object('project', x.project,
                                  'days',    MAX(x.days),
                                  'absence', bool_or(x.absence))
        FROM (
            SELECT e.value->>'project'                                   AS project,
                   GREATEST(COALESCE((e.value->>'days')::integer, 0), 0) AS days,
                   COALESCE((e.value->>'absence')::boolean, false)       AS absence
            FROM jsonb_array_elements(COALESCE(in_targets, '[]'::jsonb)) e
            WHERE e.value->>'project' IS NOT NULL
        ) x
        GROUP BY x.project
        ORDER BY x.project
    LOOP
        t_proj := rec->>'project';
        t_req  := (rec->>'days')::integer;

        t_idx := NULL;
        FOR i IN 1..n LOOP
            IF proj[i] = t_proj THEN
                t_idx := i;
                EXIT;
            END IF;
        END LOOP;

        IF t_idx IS NULL THEN
            n           := n + 1;
            proj        := array_append(proj,        t_proj);
            days        := array_append(days,        0);
            is_abs      := array_append(is_abs,      (rec->>'absence')::boolean);
            locked      := array_append(locked,      false);
            was_target  := array_append(was_target,  false);
            before_days := array_append(before_days, 0);
            t_idx       := n;
        END IF;

        -- Room for this project = the length of the week, minus any target
        -- applied earlier in this same call.
        --
        -- Absence is deliberately NOT subtracted. Staffing Anna 5 days in a week
        -- she is away 2 of records 5, because 5 is what was asked for and it is
        -- the only version of it that survives her cancelling those 2 days. What
        -- the week will actually hold is reported in `absence` below, and drawn
        -- by the grid, rather than being enforced by throwing the request away.
        locked_sum := 0;
        FOR i IN 1..n LOOP
            IF locked[i] AND NOT is_abs[i] AND i <> t_idx THEN
                locked_sum := locked_sum + days[i];
            END IF;
        END LOOP;

        room    := GREATEST(cap - locked_sum, 0);
        granted := LEAST(t_req, room);

        IF is_abs[t_idx] THEN
            -- absence is registered in the absence calendar, not booked here
            granted := 0;
            reason  := 'absence_not_writable';
        ELSIF cap = 0 THEN
            reason := 'no_workable_days';
        ELSIF granted < t_req THEN
            -- The only way to fall short now: more days than the week has, or
            -- more than is left after something else in the same batch took its
            -- share. Both are "ikke plass i uka".
            reason := 'exceeds_week_capacity';
        ELSE
            reason := NULL;
        END IF;

        IF reason IS NOT NULL THEN
            refused := refused || jsonb_build_array(jsonb_build_object(
                'project',        t_proj,
                'requested_days', t_req,
                'granted_days',   granted,
                'shortfall_days', t_req - granted,
                'reason',         reason,
                -- Always empty now, and kept only so the shape does not change
                -- under a client that reads it. Absence blocks nothing, so
                -- listing the week's absence codes against a refusal caused by
                -- the length of the week would read as a cause it is not.
                -- `absence.blocked_by` is where those codes belong.
                'blocked_by',     '[]'::jsonb
            ));
        END IF;

        -- never write absence
        CONTINUE WHEN is_abs[t_idx];

        days[t_idx]       := granted;
        locked[t_idx]     := true;
        was_target[t_idx] := true;

        -- ---- displace: shave one day off the largest movable, then look again
        --
        -- `total` adds up the bookings and skips absence. That skip is the fix:
        -- a week's worth of work has to fit in a week, but absence is not work
        -- being planned and must not push aside work that already is.
        --
        -- Anna has 3 days ANE1006 and 2 days off. Book her 2 days of KUN1001:
        --
        --   counting absence  3 + 2 + 2 = 7, two over a 5-day week, so ANE1006 is
        --                     shaved to 1 and saved that way. She cancels the 2
        --                     days off and is on 3 of 5, with nothing left to say
        --                     where the other 2 went.
        --
        --   bookings only     3 + 2 = 5, which fits, so ANE1006 keeps its 3. The
        --                     grid still draws the week as full, because the
        --                     absence is drawn over the top of it. She cancels,
        --                     and the full week is simply there again.
        LOOP
            total := 0;
            FOR i IN 1..n LOOP
                IF NOT is_abs[i] THEN
                    total := total + days[i];
                END IF;
            END LOOP;

            over := total - cap;
            EXIT WHEN over <= 0;

            big_idx := 0;
            big_val := 0;
            FOR i IN 1..n LOOP
                -- strict > means the FIRST maximum wins, and the arrays are
                -- sorted by project code, so ties break lowest-code-first
                IF NOT locked[i] AND days[i] > big_val THEN
                    big_val := days[i];
                    big_idx := i;
                END IF;
            END LOOP;

            EXIT WHEN big_idx = 0;  -- nothing movable left to give

            days[big_idx] := days[big_idx] - 1;
        END LOOP;
    END LOOP;

    -- ---- results ------------------------------------------------------------
    total := 0;
    FOR i IN 1..n LOOP
        allocations := allocations || jsonb_build_array(jsonb_build_object(
            'project', proj[i],
            'days',    days[i],
            'absence', is_abs[i]
        ));

        IF NOT is_abs[i] THEN
            total := total + days[i];
        END IF;

        IF NOT was_target[i] AND NOT is_abs[i] AND days[i] <> before_days[i] THEN
            displaced := displaced || jsonb_build_array(jsonb_build_object(
                'project',     proj[i],
                'days_before', before_days[i],
                'days_after',  days[i]
            ));
        END IF;
    END LOOP;

    -- How much of the plan the absence covers. The same arithmetic the grid
    -- draws with: the days left after absence are all that can hold work, and
    -- anything planned beyond them is not going to happen.
    --
    -- Nothing here changes what is written. It is what lets a caller say "saved,
    -- and 2 of those days are ferie" instead of either lying or refusing.
    hidden := GREATEST(total - GREATEST(cap - absence_days, 0), 0);

    RETURN jsonb_build_object(
        'capacity_days', cap,
        'allocations',   allocations,
        'displaced',     displaced,
        'refused',       refused,
        'absence',       jsonb_build_object(
                             'days',        absence_days,
                             'hidden_days', hidden,
                             'blocked_by',  to_jsonb(blocked_by),
                             'protected',   has_protected)
    );
END
$$ LANGUAGE plpgsql IMMUTABLE;


-- -----------------------------------------------------------------------------
-- Apply a batch of weekly staffing changes.
--
--   in_payload  [{"employee":42,"week":"2026-33","project":"ANE1006","days":3}, ...]
--   in_dry_run  true = work out the answer and return it, write nothing.
--               The grid uses this for its "3 will be refused" preview, so the
--               preview and the real thing can never disagree.
--
-- One transaction for the whole batch. Refusals come back in the result rather
-- than as an exception, so nothing is ever left half-applied.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_weekly_staffing(
    in_payload jsonb,
    in_dry_run boolean DEFAULT false
) RETURNS jsonb
AS $$
DECLARE
    grp           record;
    week_start    date;
    cap           integer;
    current_state jsonb;
    plan          jsonb;
    alloc         jsonb;
    pre_state     jsonb;
    post_state    jsonb;
    weeks_out     jsonb   := '[]'::jsonb;
    undo_out      jsonb   := '[]'::jsonb;
    applied       integer := 0;
    refused_n     integer := 0;
    pct           integer;
BEGIN
    FOR grp IN
        SELECT (e.value->>'employee')::integer AS employee,
               e.value->>'week'                AS week,
               jsonb_agg(jsonb_build_object(
                   'project', e.value->>'project',
                   'days',    GREATEST(COALESCE((e.value->>'days')::integer, 0), 0),
                   'absence', is_absence_reason(e.value->>'project')
               ) ORDER BY e.value->>'project') AS targets
        FROM jsonb_array_elements(COALESCE(in_payload, '[]'::jsonb)) e
        WHERE e.value->>'employee' IS NOT NULL
          AND e.value->>'week'     IS NOT NULL
          AND e.value->>'project'  IS NOT NULL
        GROUP BY 1, 2
        ORDER BY 1, 2
    LOOP
        week_start := to_date(grp.week || '-1', 'IYYY-IW-ID');

        -- Serialise concurrent planners on this one person-week, so two people
        -- cannot both decide "there is room for 3 days" and clobber each other.
        IF NOT in_dry_run THEN
            PERFORM pg_advisory_xact_lock(
                hashtext('weekly_staffing:' || grp.employee || ':' || grp.week));
        END IF;

        SELECT COUNT(*)::integer
        INTO cap
        FROM available_dates_new(week_start, (week_start + 4)::date);

        -- Current state in whole days. Absence days are counted the same way
        -- get_weekly_staffing_json reports them (one row = one whole day), so
        -- what we write agrees with what the grid reads.
        --
        -- Each absent DATE is attributed to exactly one reason before the
        -- grouping. `absence` is keyed by (employee_id, reason, date), so one
        -- Tuesday can carry both ferie and fagutvikling — and plan_weekly_staffing
        -- adds these entries up to decide how full the week is. Grouping by
        -- reason alone therefore made that Tuesday two days gone out of five, so
        -- a person on ferie Monday to Wednesday with a fagdag on the Tuesday had
        -- one of their two genuinely free days refused as blocked_by_absence.
        -- overbooked_weeks below has always counted COUNT(DISTINCT a.date)
        -- across reasons; this is the same rule, so the two agree.
        --
        -- Protected first, so a day of ferie is never relabelled as the
        -- fagutvikling sharing it, then reason, so the pick is deterministic.
        SELECT COALESCE(jsonb_agg(t.x ORDER BY t.x->>'project'), '[]'::jsonb)
        INTO current_state
        FROM (
            SELECT jsonb_build_object(
                       'project', s.project,
                       'days',    ROUND(SUM(s.percentage) / 100.0)::integer,
                       'absence', false) AS x
            FROM staffing s
            WHERE s.employee = grp.employee
              AND s.date BETWEEN week_start AND (week_start + 4)::date
            GROUP BY s.project
            UNION ALL
            SELECT jsonb_build_object(
                       'project', d.reason,
                       'days',    COUNT(*)::integer,
                       'absence', true) AS x
            FROM (
                SELECT DISTINCT ON (a.date) a.date, a.reason
                FROM absence a
                WHERE a.employee_id = grp.employee
                  AND a.date BETWEEN week_start AND (week_start + 4)::date
                ORDER BY a.date, is_protected_absence(a.reason) DESC, a.reason
            ) d
            GROUP BY d.reason
        ) t;

        -- what to put back if this batch is undone (staffing only)
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'project', e.value->>'project',
                   'days',    (e.value->>'days')::integer)
                   ORDER BY e.value->>'project'), '[]'::jsonb)
        INTO pre_state
        FROM jsonb_array_elements(current_state) e
        WHERE COALESCE((e.value->>'absence')::boolean, false) = false
          AND (e.value->>'days')::integer > 0;

        plan := plan_weekly_staffing(current_state, grp.targets, cap);

        IF NOT in_dry_run THEN
            FOR alloc IN SELECT e.value FROM jsonb_array_elements(plan->'allocations') e
            LOOP
                CONTINUE WHEN COALESCE((alloc->>'absence')::boolean, false);

                IF (alloc->>'days')::integer > 0 AND cap > 0 THEN
                    pct := ROUND((alloc->>'days')::integer * 100.0 / cap)::integer;
                    PERFORM upsert_staffing(grp.employee, alloc->>'project',
                                            week_start, (week_start + 4)::date, pct);
                ELSE
                    PERFORM remove_staffing(grp.employee, alloc->>'project',
                                            week_start, (week_start + 4)::date);
                END IF;
            END LOOP;
        END IF;

        -- what we expect to find if this batch is undone later
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'project', e.value->>'project',
                   'days',    (e.value->>'days')::integer)
                   ORDER BY e.value->>'project'), '[]'::jsonb)
        INTO post_state
        FROM jsonb_array_elements(plan->'allocations') e
        WHERE COALESCE((e.value->>'absence')::boolean, false) = false
          AND (e.value->>'days')::integer > 0;

        weeks_out := weeks_out || jsonb_build_array(
            jsonb_build_object('employee', grp.employee, 'week', grp.week) || plan);

        undo_out := undo_out || jsonb_build_array(jsonb_build_object(
            'employee', grp.employee,
            'week',     grp.week,
            'expect',   post_state,
            'restore',  pre_state));

        -- A week that got SOME of what it asked for is a save, not a refusal.
        -- Asking for 5 days in a week that only holds 4 produces a shortfall,
        -- and counting that as refused made a batch that filled every cell
        -- report "nothing saved". The shortfall is still reported per project
        -- in `refused`, which is where the detail belongs.
        IF jsonb_array_length(plan->'refused') > 0
           AND NOT EXISTS (
               SELECT 1
               FROM jsonb_array_elements(plan->'refused') r
               WHERE (r.value->>'granted_days')::integer > 0
           )
        THEN
            refused_n := refused_n + 1;
        ELSE
            applied := applied + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'dry_run',       in_dry_run,
        'applied_weeks', applied,
        'refused_weeks', refused_n,
        'weeks',         weeks_out,
        'undo',          undo_out
    );
END
$$ LANGUAGE plpgsql;


-- -----------------------------------------------------------------------------
-- Undo a batch, using the `undo` block returned by apply_weekly_staffing.
--
-- Compare-and-set: each person-week is only restored if it still looks exactly
-- as this batch left it. If somebody else has edited it since, that week is
-- skipped and reported as "changed_since" rather than trampling their work.
--
-- Restores with no capacity check on purpose — putting a week back the way it
-- was must succeed even when the old state was already over 100%, which
-- historical rows written by add_staffing_in_period can be.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.restore_weekly_staffing(in_snapshot jsonb)
RETURNS jsonb
AS $$
DECLARE
    snap       jsonb;
    emp        integer;
    wk         text;
    week_start date;
    cap        integer;
    actual     jsonb;
    expect     jsonb;
    restore    jsonb;
    entry      jsonb;
    pct        integer;
    restored   integer := 0;
    skipped    integer := 0;
    weeks_out  jsonb   := '[]'::jsonb;
BEGIN
    FOR snap IN SELECT e.value FROM jsonb_array_elements(COALESCE(in_snapshot, '[]'::jsonb)) e
    LOOP
        emp        := (snap->>'employee')::integer;
        wk         := snap->>'week';
        week_start := to_date(wk || '-1', 'IYYY-IW-ID');

        PERFORM pg_advisory_xact_lock(hashtext('weekly_staffing:' || emp || ':' || wk));

        SELECT COALESCE(jsonb_agg(jsonb_build_object('project', t.project, 'days', t.days)
                                  ORDER BY t.project), '[]'::jsonb)
        INTO actual
        FROM (
            SELECT s.project AS project,
                   ROUND(SUM(s.percentage) / 100.0)::integer AS days
            FROM staffing s
            WHERE s.employee = emp
              AND s.date BETWEEN week_start AND (week_start + 4)::date
            GROUP BY s.project
            HAVING ROUND(SUM(s.percentage) / 100.0)::integer > 0
        ) t;

        expect  := COALESCE(snap->'expect',  '[]'::jsonb);
        restore := COALESCE(snap->'restore', '[]'::jsonb);

        IF actual <> expect THEN
            skipped   := skipped + 1;
            weeks_out := weeks_out || jsonb_build_array(jsonb_build_object(
                'employee', emp, 'week', wk, 'status', 'changed_since'));
            CONTINUE;
        END IF;

        SELECT COUNT(*)::integer
        INTO cap
        FROM available_dates_new(week_start, (week_start + 4)::date);

        -- anything there now that the snapshot does not mention has to go
        FOR entry IN SELECT e.value FROM jsonb_array_elements(actual) e
        LOOP
            IF NOT EXISTS (
                SELECT 1 FROM jsonb_array_elements(restore) r
                WHERE r.value->>'project' = entry->>'project'
            ) THEN
                PERFORM remove_staffing(emp, entry->>'project',
                                        week_start, (week_start + 4)::date);
            END IF;
        END LOOP;

        FOR entry IN SELECT e.value FROM jsonb_array_elements(restore) e
        LOOP
            IF (entry->>'days')::integer > 0 AND cap > 0 THEN
                pct := ROUND((entry->>'days')::integer * 100.0 / cap)::integer;
                PERFORM upsert_staffing(emp, entry->>'project',
                                        week_start, (week_start + 4)::date, pct);
            ELSE
                PERFORM remove_staffing(emp, entry->>'project',
                                        week_start, (week_start + 4)::date);
            END IF;
        END LOOP;

        restored  := restored + 1;
        weeks_out := weeks_out || jsonb_build_array(jsonb_build_object(
            'employee', emp, 'week', wk, 'status', 'restored'));
    END LOOP;

    RETURN jsonb_build_object(
        'restored_weeks', restored,
        'skipped_weeks',  skipped,
        'weeks',          weeks_out
    );
END
$$ LANGUAGE plpgsql;


-- -----------------------------------------------------------------------------
-- Read-only: person-weeks that are booked past their capacity.
--
-- Nothing stops this existing in historical data — there has never been a
-- capacity constraint in the database, and there deliberately still isn't one
-- (a weekly cross-row sum cannot be a CHECK, and a trigger would reject
-- legitimate corrections to rows that are already overbooked). The invariant
-- is enforced in one write path; this is how reports find the rest.
--
-- Absence is not taken out of the plan, so a full week that somebody later took
-- time off in shows up here. That is expected rather than a fault. The invariant
-- still worth checking is the bookings alone fitting the week: for that, drop
-- the join to `away` and compare `s.d` to `cap` on its own.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.overbooked_weeks(start_date date, end_date date)
RETURNS TABLE (
    employee_id   integer,
    iso_week      text,
    booked_days   numeric,
    capacity_days integer
)
AS $$
BEGIN
    RETURN QUERY
    WITH staffed AS (
        SELECT s.employee                                        AS emp,
               TO_CHAR(DATE_TRUNC('week', s.date), 'IYYY-IW')    AS wk,
               DATE_TRUNC('week', s.date)::date                  AS wk_start,
               SUM(s.percentage) / 100.0                         AS d
        FROM staffing s
        WHERE s.date BETWEEN start_date AND end_date
        GROUP BY 1, 2, 3
    ),
    away AS (
        SELECT a.employee_id                                     AS emp,
               TO_CHAR(DATE_TRUNC('week', a.date), 'IYYY-IW')    AS wk,
               COUNT(DISTINCT a.date)::numeric                   AS d
        FROM absence a
        WHERE a.date BETWEEN start_date AND end_date
        GROUP BY 1, 2
    ),
    combined AS (
        SELECT s.emp,
               s.wk,
               s.d + COALESCE(w.d, 0) AS booked,
               (SELECT COUNT(*)::integer
                  FROM available_dates_new(s.wk_start, (s.wk_start + 4)::date)) AS cap
        FROM staffed s
        LEFT JOIN away w ON w.emp = s.emp AND w.wk = s.wk
    )
    SELECT c.emp, c.wk, c.booked, c.cap
    FROM combined c
    WHERE c.booked > c.cap
    ORDER BY c.emp, c.wk;
END
$$ LANGUAGE plpgsql STABLE;
