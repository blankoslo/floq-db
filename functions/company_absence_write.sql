-- Booking company absence (fagdag) for many people at once.
-- Does not touch `staffing`. Refusals are returned as values, not exceptions.

-- Which absence reasons may be booked on someone else's behalf.
CREATE OR REPLACE FUNCTION public.is_bookable_absence(reason text)
        RETURNS boolean AS
$$
BEGIN
  RETURN reason = 'FAG1000';  -- Fagutvikling
END
$$ LANGUAGE plpgsql IMMUTABLE;

-- Book one absence reason for many people on the given dates.
-- Returns {dry_run, reason, booked, refused, people, undo}.
-- Per person-date status: booked (in `undo`), already_booked (not in `undo`,
-- so undo never removes a pre-existing row), blocked_by_absence (skipped;
-- `blocked_by` names the other reason).
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

    -- Refuse the whole batch on a non-working day; `absence` has a CHECK that
    -- would otherwise fail it.
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
            -- Same lock key as the weekly staffing writes.
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
        'undo',    jsonb_build_object(
                       'reason', in_reason,
                       'rows',   CASE WHEN in_dry_run THEN '[]'::jsonb ELSE undo_rows END)
    );
END
$$ LANGUAGE plpgsql;

-- Undo apply_company_absence, given its `undo` block.
-- Deletes only the exact (employee, reason, date) rows listed, so other
-- absence on the same day is kept. Rows already gone count as `skipped`.
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
