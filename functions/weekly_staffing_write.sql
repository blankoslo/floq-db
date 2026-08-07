-- =============================================================================
-- Weekly staffing capacity — the company rule, in one place.
--
-- The rule: a person's week holds at most `capacity_days` working days.
-- Booking days that do not fit takes them from work already booked that week,
-- largest allocation first, one day at a time. Absence is NEVER taken from —
-- it lives in a different table and is only ever changed in the absence
-- calendar.
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
--     "refused":     [{"project":"X","requested_days":4,"granted_days":1,
--                      "shortfall_days":3,"reason":"...","blocked_by":["FER1000"]}] }
--
-- `allocations` is the complete intended end state for the week, including
-- entries at 0 days so the caller knows to delete them, and including absence
-- (flagged) so a UI can draw the whole week. The caller must not write absence.
--
-- `reason` is a closed set:
--   exceeds_week_capacity | blocked_by_protected_absence | blocked_by_absence
--   absence_not_writable  | no_workable_days
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

        -- room for this project = capacity minus everything already locked
        -- (absence, plus any target applied earlier in this same call)
        locked_sum := 0;
        FOR i IN 1..n LOOP
            IF locked[i] AND i <> t_idx THEN
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
            IF t_req > cap THEN
                reason := 'exceeds_week_capacity';
            ELSIF absence_days > 0 THEN
                reason := CASE WHEN has_protected
                               THEN 'blocked_by_protected_absence'
                               ELSE 'blocked_by_absence'
                          END;
            ELSE
                reason := 'exceeds_week_capacity';
            END IF;
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
                'blocked_by',     to_jsonb(blocked_by)
            ));
        END IF;

        -- never write absence
        CONTINUE WHEN is_abs[t_idx];

        days[t_idx]       := granted;
        locked[t_idx]     := true;
        was_target[t_idx] := true;

        -- ---- displace: shave one day off the largest movable, then look again
        LOOP
            total := 0;
            FOR i IN 1..n LOOP
                total := total + days[i];
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
    FOR i IN 1..n LOOP
        allocations := allocations || jsonb_build_array(jsonb_build_object(
            'project', proj[i],
            'days',    days[i],
            'absence', is_abs[i]
        ));

        IF NOT was_target[i] AND NOT is_abs[i] AND days[i] <> before_days[i] THEN
            displaced := displaced || jsonb_build_array(jsonb_build_object(
                'project',     proj[i],
                'days_before', before_days[i],
                'days_after',  days[i]
            ));
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'capacity_days', cap,
        'allocations',   allocations,
        'displaced',     displaced,
        'refused',       refused
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
