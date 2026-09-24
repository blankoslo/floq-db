-- Weekly staffing writes.
--
-- Each project in a person-week is capped at the length of the week (its
-- weekday count, always 5). Bookings never displace each other, so a week may
-- sum past its capacity (overbooked). Absence and holidays are never subtracted
-- from stored rows: anything turning staffing rows into hours must subtract
-- them itself, and must not assume a week sums to its capacity.
--
-- Amounts are days on the wire and may be fractional, to the hundredth
-- (5 hours = 0.67 days). Internally they are points: 100 points is one day, a
-- week of five is 500, and a project's points are spread over the week's five
-- weekdays with any remainder one point each on the first days
-- (67 -> 14,14,13,13,13). A whole number of days reads back exactly.

-- -----------------------------------------------------------------------------
-- Points (hundredths of a day) as days: 300 -> 3, 67 -> 0.67.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.staffing_points_to_days(in_points integer)
        RETURNS numeric AS
$$
  SELECT CASE WHEN in_points % 100 = 0 THEN (in_points / 100)::numeric
              ELSE ROUND(in_points / 100.0, 2) END;
$$ LANGUAGE sql IMMUTABLE;


-- -----------------------------------------------------------------------------
-- Days, possibly fractional, as whole points: 0.667 -> 67. Negative is 0.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.staffing_days_to_points(in_days text)
        RETURNS integer AS
$$
  SELECT GREATEST(ROUND(COALESCE(in_days::numeric, 0) * 100), 0)::integer;
$$ LANGUAGE sql IMMUTABLE;

-- -----------------------------------------------------------------------------
-- True for absence that cannot be moved (ferie, sykdom, permisjon).
-- Not the same set as is_absence_reason().
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
-- Plan one person-week. Pure: reads no tables.
--
--   in_current  [{"project":"ANE1006","days":3,"absence":false}, ...]
--   in_targets  [{"project":"ANE1006","days":0.67,"absence":false}, ...]
--
-- Callers must set "absence" themselves (e.g. via is_absence_reason).
-- Days may be fractional; they are rounded to the hundredth.
--
-- Returns:
--   { "capacity_days": 5,
--     "allocations": [{"project":"X","days":2,"absence":false}, ...],
--     "displaced":   [],
--     "refused":     [{"project":"X","requested_days":6,"granted_days":5,
--                      "shortfall_days":1,"reason":"...","blocked_by":[]}],
--     "absence":     {"days":2,"hidden_days":2,"blocked_by":["FER1000"],
--                     "protected":true} }
--
-- `allocations` is the full end state, including 0-day entries (to delete) and
-- absence (flagged; must not be written). `displaced` and `refused.blocked_by`
-- are always empty, kept for older clients. `absence.hidden_days` is how many planned days the absence
-- covers.
--
-- reason: exceeds_week_capacity | absence_not_writable | no_workable_days
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.plan_weekly_staffing(
    in_current       jsonb,
    in_targets       jsonb,
    in_capacity_days integer DEFAULT 5
) RETURNS jsonb
AS $$
DECLARE
    cap           integer   := GREATEST(COALESCE(in_capacity_days, 0), 0) * 100;
    n             integer   := 0;
    proj          text[]    := ARRAY[]::text[];
    pts           integer[] := ARRAY[]::integer[];
    is_abs        boolean[] := ARRAY[]::boolean[];
    locked        boolean[] := ARRAY[]::boolean[];
    was_target    boolean[] := ARRAY[]::boolean[];
    before_pts    integer[] := ARRAY[]::integer[];
    blocked_by    text[]    := ARRAY[]::text[];
    has_protected boolean   := false;
    absence_pts   integer   := 0;
    rec           jsonb;
    i             integer;
    t_proj        text;
    t_req         integer;
    t_idx         integer;
    granted       integer;
    reason        text;
    total         integer;
    hidden        integer   := 0;
    allocations   jsonb     := '[]'::jsonb;
    displaced     jsonb     := '[]'::jsonb;
    refused       jsonb     := '[]'::jsonb;
BEGIN
    -- ---- load the week as it stands, merged by project, sorted for determinism
    FOR rec IN
        SELECT jsonb_build_object('project', x.project,
                                  'points',  SUM(x.points),
                                  'absence', bool_or(x.absence))
        FROM (
            SELECT e.value->>'project'                               AS project,
                   staffing_days_to_points(e.value->>'days')         AS points,
                   COALESCE((e.value->>'absence')::boolean, false)   AS absence
            FROM jsonb_array_elements(COALESCE(in_current, '[]'::jsonb)) e
            WHERE e.value->>'project' IS NOT NULL
        ) x
        GROUP BY x.project
        ORDER BY x.project
    LOOP
        n          := n + 1;
        proj       := array_append(proj,       rec->>'project');
        pts        := array_append(pts,        (rec->>'points')::integer);
        is_abs     := array_append(is_abs,     (rec->>'absence')::boolean);
        was_target := array_append(was_target, false);
    END LOOP;

    before_pts := pts;

    -- absence is locked from the start and counts against the week
    FOR i IN 1..n LOOP
        locked := array_append(locked, is_abs[i]);
        IF is_abs[i] THEN
            absence_pts := absence_pts + pts[i];
            blocked_by  := array_append(blocked_by, proj[i]);
            IF is_protected_absence(proj[i]) THEN
                has_protected := true;
            END IF;
        END IF;
    END LOOP;

    -- ---- apply each target in turn -----------------------------------------
    -- A project named twice in the targets gets the larger amount.
    FOR rec IN
        SELECT jsonb_build_object('project', x.project,
                                  'points',  MAX(x.points),
                                  'absence', bool_or(x.absence))
        FROM (
            SELECT e.value->>'project'                               AS project,
                   staffing_days_to_points(e.value->>'days')         AS points,
                   COALESCE((e.value->>'absence')::boolean, false)   AS absence
            FROM jsonb_array_elements(COALESCE(in_targets, '[]'::jsonb)) e
            WHERE e.value->>'project' IS NOT NULL
        ) x
        GROUP BY x.project
        ORDER BY x.project
    LOOP
        t_proj := rec->>'project';
        t_req  := (rec->>'points')::integer;

        t_idx := NULL;
        FOR i IN 1..n LOOP
            IF proj[i] = t_proj THEN
                t_idx := i;
                EXIT;
            END IF;
        END LOOP;

        IF t_idx IS NULL THEN
            n          := n + 1;
            proj       := array_append(proj,       t_proj);
            pts        := array_append(pts,        0);
            is_abs     := array_append(is_abs,     (rec->>'absence')::boolean);
            locked     := array_append(locked,     false);
            was_target := array_append(was_target, false);
            before_pts := array_append(before_pts, 0);
            t_idx      := n;
        END IF;

        -- Capped at the week alone, ignoring other bookings and absence.
        granted := LEAST(t_req, cap);

        IF is_abs[t_idx] THEN
            granted := 0;
            reason  := 'absence_not_writable';
        ELSIF cap = 0 THEN
            reason := 'no_workable_days';
        ELSIF granted < t_req THEN
            reason := 'exceeds_week_capacity';
        ELSE
            reason := NULL;
        END IF;

        IF reason IS NOT NULL THEN
            refused := refused || jsonb_build_array(jsonb_build_object(
                'project',        t_proj,
                'requested_days', staffing_points_to_days(t_req),
                'granted_days',   staffing_points_to_days(granted),
                'shortfall_days', staffing_points_to_days(t_req - granted),
                'reason',         reason,
                'blocked_by',     '[]'::jsonb
            ));
        END IF;

        CONTINUE WHEN is_abs[t_idx];

        pts[t_idx]        := granted;
        locked[t_idx]     := true;
        was_target[t_idx] := true;
    END LOOP;

    -- ---- results ------------------------------------------------------------
    total := 0;
    FOR i IN 1..n LOOP
        allocations := allocations || jsonb_build_array(jsonb_build_object(
            'project', proj[i],
            'days',    staffing_points_to_days(pts[i]),
            'absence', is_abs[i]
        ));

        IF NOT is_abs[i] THEN
            total := total + pts[i];
        END IF;

        IF NOT was_target[i] AND NOT is_abs[i] AND pts[i] <> before_pts[i] THEN
            displaced := displaced || jsonb_build_array(jsonb_build_object(
                'project',     proj[i],
                'days_before', staffing_points_to_days(before_pts[i]),
                'days_after',  staffing_points_to_days(pts[i])
            ));
        END IF;
    END LOOP;

    -- Planned time beyond what is left of the week after absence.
    hidden := GREATEST(total - GREATEST(cap - absence_pts, 0), 0);

    RETURN jsonb_build_object(
        'capacity_days', cap / 100,
        'allocations',   allocations,
        'displaced',     displaced,
        'refused',       refused,
        'absence',       jsonb_build_object(
                             'days',        staffing_points_to_days(absence_pts),
                             'hidden_days', staffing_points_to_days(hidden),
                             'blocked_by',  to_jsonb(blocked_by),
                             'protected',   has_protected)
    );
END
$$ LANGUAGE plpgsql IMMUTABLE;


-- -----------------------------------------------------------------------------
-- Write one project's rows for every weekday in the range, holidays included
-- (unlike upsert_staffing(), which skips holidays), so a plan reads back at the
-- size it was made. Returns the dates written.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_weekly_staffing(
    in_employee    integer,
    in_project     text,
    start_date     date,
    end_date       date,
    in_percentage  integer DEFAULT 100
) RETURNS SETOF date
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM absence_reasons WHERE id = in_project) THEN
        RAISE EXCEPTION 'Cannot insert absence into the staffing table: "%"', in_project;
    END IF;

    DELETE FROM staffing
    WHERE employee = in_employee
      AND project  = in_project
      AND date BETWEEN start_date AND end_date;

    RETURN QUERY (
        WITH new_staffing AS (
            INSERT INTO staffing (employee, project, date, percentage)
            SELECT in_employee, in_project, w.weekday_date, in_percentage
            FROM weekday_dates(start_date, end_date) w
            ON CONFLICT (employee, project, date) DO NOTHING
            RETURNING date
        )
        SELECT date FROM new_staffing ORDER BY date
    );
END
$$ LANGUAGE plpgsql;


-- -----------------------------------------------------------------------------
-- Write one project's week as a total of points over its five weekdays,
-- holidays included, the remainder one point each on the first days. 0 points
-- removes the week. Returns the dates written.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.write_weekly_staffing_points(
    in_employee   integer,
    in_project    text,
    in_week_start date,
    in_points     integer
) RETURNS SETOF date
AS $$
DECLARE
    n integer;
BEGIN
    IF EXISTS (SELECT 1 FROM absence_reasons WHERE id = in_project) THEN
        RAISE EXCEPTION 'Cannot insert absence into the staffing table: "%"', in_project;
    END IF;

    DELETE FROM staffing
    WHERE employee = in_employee
      AND project  = in_project
      AND date BETWEEN in_week_start AND (in_week_start + 4)::date;

    SELECT COUNT(*)::integer INTO n
    FROM weekday_dates(in_week_start, (in_week_start + 4)::date);

    IF n = 0 OR COALESCE(in_points, 0) <= 0 THEN
        RETURN;
    END IF;

    RETURN QUERY (
        WITH spread AS (
            SELECT w.weekday_date AS date,
                   in_points / n
                   + CASE WHEN ROW_NUMBER() OVER (ORDER BY w.weekday_date) <= in_points % n
                          THEN 1 ELSE 0 END AS percentage
            FROM weekday_dates(in_week_start, (in_week_start + 4)::date) w
        ),
        new_staffing AS (
            INSERT INTO staffing (employee, project, date, percentage)
            SELECT in_employee, in_project, s.date, s.percentage
            FROM spread s
            WHERE s.percentage > 0
            RETURNING date
        )
        SELECT date FROM new_staffing ORDER BY date
    );
END
$$ LANGUAGE plpgsql;


-- -----------------------------------------------------------------------------
-- Apply a batch of weekly staffing changes.
--
--   in_payload  [{"employee":42,"week":"2026-33","project":"ANE1006","days":3}, ...]
--               days may be fractional: 0.67 is five hours.
--   in_dry_run  true = return the result without writing anything.
--
-- Refusals are returned in the result, not raised. The result includes an
-- `undo` block for restore_weekly_staffing().
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
BEGIN
    FOR grp IN
        SELECT (e.value->>'employee')::integer AS employee,
               e.value->>'week'                AS week,
               jsonb_agg(jsonb_build_object(
                   'project', e.value->>'project',
                   'days',    staffing_points_to_days(staffing_days_to_points(e.value->>'days')),
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

        -- Serialise concurrent writers on this person-week.
        IF NOT in_dry_run THEN
            PERFORM pg_advisory_xact_lock(
                hashtext('weekly_staffing:' || grp.employee || ':' || grp.week));
        END IF;

        -- Length of the week, not its workable days: holidays do not shorten it.
        SELECT COUNT(*)::integer
        INTO cap
        FROM weekday_dates(week_start, (week_start + 4)::date);

        -- Current state in days, to the hundredth. A date with several absence reasons
        -- counts once, under one reason (protected first).
        SELECT COALESCE(jsonb_agg(t.x ORDER BY t.x->>'project'), '[]'::jsonb)
        INTO current_state
        FROM (
            SELECT jsonb_build_object(
                       'project', s.project,
                       'days',    staffing_points_to_days(SUM(s.percentage)::integer),
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
                   'days',    e.value->'days')
                   ORDER BY e.value->>'project'), '[]'::jsonb)
        INTO pre_state
        FROM jsonb_array_elements(current_state) e
        WHERE COALESCE((e.value->>'absence')::boolean, false) = false
          AND (e.value->>'days')::numeric > 0;

        plan := plan_weekly_staffing(current_state, grp.targets, cap);

        IF NOT in_dry_run THEN
            FOR alloc IN SELECT e.value FROM jsonb_array_elements(plan->'allocations') e
            LOOP
                CONTINUE WHEN COALESCE((alloc->>'absence')::boolean, false);

                IF cap > 0 THEN
                    PERFORM write_weekly_staffing_points(
                        grp.employee, alloc->>'project', week_start,
                        staffing_days_to_points(alloc->>'days'));
                ELSE
                    PERFORM remove_staffing(grp.employee, alloc->>'project',
                                            week_start, (week_start + 4)::date);
                END IF;
            END LOOP;
        END IF;

        -- what we expect to find if this batch is undone later
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'project', e.value->>'project',
                   'days',    e.value->'days')
                   ORDER BY e.value->>'project'), '[]'::jsonb)
        INTO post_state
        FROM jsonb_array_elements(plan->'allocations') e
        WHERE COALESCE((e.value->>'absence')::boolean, false) = false
          AND (e.value->>'days')::numeric > 0;

        weeks_out := weeks_out || jsonb_build_array(
            jsonb_build_object('employee', grp.employee, 'week', grp.week) || plan);

        undo_out := undo_out || jsonb_build_array(jsonb_build_object(
            'employee', grp.employee,
            'week',     grp.week,
            'expect',   post_state,
            'restore',  pre_state));

        -- A week counts as refused only if no refused entry got any days.
        IF jsonb_array_length(plan->'refused') > 0
           AND NOT EXISTS (
               SELECT 1
               FROM jsonb_array_elements(plan->'refused') r
               WHERE (r.value->>'granted_days')::numeric > 0
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
-- Compare-and-set: a person-week is restored only if it still matches `expect`;
-- otherwise it is skipped as "changed_since". No capacity check.
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
                   staffing_points_to_days(SUM(s.percentage)::integer) AS days
            FROM staffing s
            WHERE s.employee = emp
              AND s.date BETWEEN week_start AND (week_start + 4)::date
            GROUP BY s.project
            HAVING SUM(s.percentage) > 0
        ) t;

        expect  := COALESCE(snap->'expect',  '[]'::jsonb);
        restore := COALESCE(snap->'restore', '[]'::jsonb);

        IF actual <> expect THEN
            skipped   := skipped + 1;
            weeks_out := weeks_out || jsonb_build_array(jsonb_build_object(
                'employee', emp, 'week', wk, 'status', 'changed_since'));
            CONTINUE;
        END IF;

        -- Length of the week, not its workable days.
        SELECT COUNT(*)::integer
        INTO cap
        FROM weekday_dates(week_start, (week_start + 4)::date);

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
            IF cap > 0 THEN
                PERFORM write_weekly_staffing_points(
                    emp, entry->>'project', week_start,
                    staffing_days_to_points(entry->>'days'));
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
-- Read-only: person-weeks where staffing plus absence days exceed the week's
-- weekday count.
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
                  FROM weekday_dates(s.wk_start, (s.wk_start + 4)::date)) AS cap
        FROM staffed s
        LEFT JOIN away w ON w.emp = s.emp AND w.wk = s.wk
    )
    SELECT c.emp, c.wk, c.booked, c.cap
    FROM combined c
    WHERE c.booked > c.cap
    ORDER BY c.emp, c.wk;
END
$$ LANGUAGE plpgsql STABLE;
