-- =============================================================================
-- Booking absence for many people at once — the fagdag.
--
-- The one absence write that does not come from the fraværskalender. A fagdag
-- is decided for the company rather than by the person, so it is planned in the
-- staffing grid, next to the work it is being planned around, and applied to
-- everybody in one transaction.
--
-- What this is NOT: a general way to write absence. Ferie, sykdom and permisjon
-- belong to the person and stay in the calendar. The reason must be one the
-- caller may book — see is_bookable_absence() below — and the client offers
-- exactly the same set.
--
-- It does NOT touch `staffing`. Registering absence has never removed a
-- booking (add_staffing_in_period has always written one table or the other),
-- and a fagdag is no different: the grid shows the day taken out of the largest
-- booking, and the week settles for real the next time somebody writes it
-- through apply_weekly_staffing.
--
-- Refusals are returned VALUES, not exceptions — same contract as
-- weekly_staffing_write.sql, so a partial result can be reported honestly.
--
-- -----------------------------------------------------------------------------
-- MAINTENANCE WARNING
--
-- functions/deploy.sh re-runs every functions/*.sql alphabetically on every
-- deploy, so everything here must stay CREATE OR REPLACE.
--
-- CHANGING ANY ARGUMENT LIST BELOW REQUIRES UN-COMMENTING THE MATCHING DROP
-- FIRST, or Postgres creates a second overload and PostgREST answers PGRST203.
--
-- DROP FUNCTION IF EXISTS public.is_bookable_absence(text);
-- DROP FUNCTION IF EXISTS public.apply_company_absence(text, date[], integer[], boolean);
-- DROP FUNCTION IF EXISTS public.restore_company_absence(jsonb);
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Which absence may be booked for somebody else.
--
-- Only fagutvikling. It is the one kind that is a company decision: everybody
-- goes to the same fagdag, and somebody has to put it in the calendar. Every
-- other reason is the person's own, and this function is the gate that says so.
--
-- Deliberately NOT the same set as is_absence_reason(): that says what absence
-- IS, this says what may be written from outside the fraværskalender. It is the
-- complement of is_protected_absence() only by coincidence today — do not
-- collapse them.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_bookable_absence(reason text)
        RETURNS boolean AS
$$
BEGIN
  RETURN reason = 'FAG1000';  -- Fagutvikling
END
$$ LANGUAGE plpgsql IMMUTABLE;


-- -----------------------------------------------------------------------------
-- Book one absence reason for many people on given dates.
--
--   in_reason     'FAG1000'
--   in_dates      the working days it lands on
--   in_employees  who it is for
--   in_dry_run    plan without writing, for the confirm step
--
-- Returns:
--   {
--     "dry_run": false,
--     "reason": "FAG1000",
--     "booked": 78,                         -- rows created
--     "refused": null,                      -- or 'not_bookable' / 'not_a_working_day'
--     "people": [
--       {"employee": 12, "date": "2026-09-22", "status": "booked"},
--       {"employee": 15, "date": "2026-09-22", "status": "already_booked"},
--       {"employee": 19, "date": "2026-09-22", "status": "blocked_by_absence",
--        "blocked_by": "FER1000"}
--     ],
--     "undo": {"reason": "FAG1000", "rows": [{"employee": 12, "date": "2026-09-22"}]}
--   }
--
-- Three outcomes per person-date, and the difference between the last two
-- matters:
--
--   booked             a row was created; it is in `undo`
--   already_booked     they had this day already — left alone, and NOT in
--                      `undo`, so undoing this batch cannot take away a
--                      fagdag somebody booked for themselves last month
--   blocked_by_absence they are away that day for another reason. Skipped.
--                      A fagdag stacked on somebody's ferie is not a day at a
--                      course, it is a wrong row in their calendar — and it is
--                      the caller who should decide what to do about it, which
--                      is why they are named in the result rather than silently
--                      dropped.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_company_absence(
    in_reason    text,
    in_dates     date[],
    in_employees integer[],
    in_dry_run   boolean DEFAULT false
)
RETURNS jsonb
AS $$
DECLARE
    d          date;
    emp        integer;
    other      text;
    booked     integer := 0;
    people_out jsonb   := '[]'::jsonb;
    undo_rows  jsonb   := '[]'::jsonb;
BEGIN
    IF NOT is_bookable_absence(in_reason) THEN
        RETURN jsonb_build_object(
            'dry_run', in_dry_run, 'reason', in_reason, 'booked', 0,
            'refused', 'not_bookable', 'people', '[]'::jsonb,
            'undo', jsonb_build_object('reason', in_reason, 'rows', '[]'::jsonb));
    END IF;

    -- A weekend or a public holiday is not a working day, and `absence` has a
    -- CHECK that would fail the whole batch on one. Refused as a value, so the
    -- caller can say which date and why instead of surfacing a constraint name.
    FOREACH d IN ARRAY COALESCE(in_dates, ARRAY[]::date[])
    LOOP
        IF is_holiday(d) OR NOT is_weekday(d) THEN
            RETURN jsonb_build_object(
                'dry_run', in_dry_run, 'reason', in_reason, 'booked', 0,
                'refused', 'not_a_working_day', 'refused_date', d,
                'people', '[]'::jsonb,
                'undo', jsonb_build_object('reason', in_reason, 'rows', '[]'::jsonb));
        END IF;
    END LOOP;

    FOREACH d IN ARRAY COALESCE(in_dates, ARRAY[]::date[])
    LOOP
        FOREACH emp IN ARRAY COALESCE(in_employees, ARRAY[]::integer[])
        LOOP
            -- Same key as the grid's writes, so a fagdag and a booking cannot
            -- race on the same person-week.
            IF NOT in_dry_run THEN
                PERFORM pg_advisory_xact_lock(
                    hashtext('weekly_staffing:' || emp || ':' ||
                             TO_CHAR(DATE_TRUNC('week', d), 'IYYY-IW')));
            END IF;

            IF EXISTS (SELECT 1 FROM absence a
                        WHERE a.employee_id = emp AND a.date = d
                          AND a.reason = in_reason) THEN
                people_out := people_out || jsonb_build_array(jsonb_build_object(
                    'employee', emp, 'date', d, 'status', 'already_booked'));
                CONTINUE;
            END IF;

            SELECT a.reason INTO other
              FROM absence a
             WHERE a.employee_id = emp AND a.date = d
             ORDER BY is_protected_absence(a.reason) DESC, a.reason
             LIMIT 1;

            IF other IS NOT NULL THEN
                people_out := people_out || jsonb_build_array(jsonb_build_object(
                    'employee', emp, 'date', d, 'status', 'blocked_by_absence',
                    'blocked_by', other));
                CONTINUE;
            END IF;

            IF NOT in_dry_run THEN
                INSERT INTO absence (employee_id, date, reason, percentage)
                VALUES (emp, d, in_reason, 100);
            END IF;

            booked     := booked + 1;
            people_out := people_out || jsonb_build_array(jsonb_build_object(
                'employee', emp, 'date', d, 'status', 'booked'));
            undo_rows  := undo_rows || jsonb_build_array(jsonb_build_object(
                'employee', emp, 'date', d));
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object(
        'dry_run', in_dry_run,
        'reason',  in_reason,
        'booked',  booked,
        'refused', NULL,
        'people',  people_out,
        -- Empty on a dry run: nothing was written, so there is nothing to undo.
        'undo',    jsonb_build_object(
                       'reason', in_reason,
                       'rows',   CASE WHEN in_dry_run THEN '[]'::jsonb ELSE undo_rows END)
    );
END
$$ LANGUAGE plpgsql;


-- -----------------------------------------------------------------------------
-- Undo a fagdag, using the `undo` block returned by apply_company_absence.
--
-- Deletes only the (employee, reason, date) triples this batch created. Three
-- filters, all load-bearing:
--
--   reason      the fraværskalender's own DELETE filters on employee and date
--               alone, so it removes whatever else is on that day. Undoing a
--               fagdag must never take somebody's ferie with it.
--   employee    only the people this batch actually booked. Anyone who already
--               had the day keeps it — they are not in the snapshot.
--   date        the day that was booked, and no other.
--
-- Rows that are already gone are simply not there to delete; they count as
-- `changed_since` rather than as an error, so an undo after somebody cleared
-- their own day still reports honestly.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.restore_company_absence(in_snapshot jsonb)
RETURNS jsonb
AS $$
DECLARE
    reason_in text;
    row_in    jsonb;
    emp       integer;
    d         date;
    gone      integer;
    removed   integer := 0;
    skipped   integer := 0;
BEGIN
    reason_in := in_snapshot->>'reason';

    IF NOT is_bookable_absence(COALESCE(reason_in, '')) THEN
        RETURN jsonb_build_object('removed', 0, 'skipped', 0, 'refused', 'not_bookable');
    END IF;

    FOR row_in IN
        SELECT e.value FROM jsonb_array_elements(COALESCE(in_snapshot->'rows', '[]'::jsonb)) e
    LOOP
        emp := (row_in->>'employee')::integer;
        d   := (row_in->>'date')::date;

        PERFORM pg_advisory_xact_lock(
            hashtext('weekly_staffing:' || emp || ':' ||
                     TO_CHAR(DATE_TRUNC('week', d), 'IYYY-IW')));

        WITH deleted AS (
            DELETE FROM absence
             WHERE employee_id = emp AND reason = reason_in AND date = d
            RETURNING 1
        )
        SELECT COUNT(*)::integer INTO gone FROM deleted;

        IF gone > 0 THEN
            removed := removed + 1;
        ELSE
            skipped := skipped + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('removed', removed, 'skipped', skipped, 'refused', NULL);
END
$$ LANGUAGE plpgsql;
