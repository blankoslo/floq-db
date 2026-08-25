-- Per employee and ISO week, the weeks whose "Bekreft avspasering" confirmation still holds.
-- Only weeks with a week_balance_confirmations row are returned.
--
-- The balance each week is checked against is its own, the same quantity floq-timetracker-v2
-- stored in week_balance_confirmations.minutes. It reads that as accumulated_overtime(sunday) -
-- accumulated_overtime(sunday - 7); both terms run from date_of_employment, so everything before
-- the week cancels and the expression below is what is left. Summed in whole minutes, never hours,
-- so the subtraction cannot land half a minute off through float error.
--
-- A week survives on floq-timetracker-v2's isBalanceConfirmed (src/lib/balanceConfirmation.ts):
-- minutes are negative, so >= means the week has not slipped past what was confirmed.

DROP FUNCTION IF EXISTS public.get_confirmed_avspasering_weeks(integer[], date, date);

CREATE OR REPLACE FUNCTION public.get_confirmed_avspasering_weeks(in_employee_ids integer[],
                                                                  in_start_date date,
                                                                  in_end_date date)
    RETURNS TABLE(
        employee_id integer,
        week_start  date
    )
    LANGUAGE sql
    STABLE
AS
$function$
    -- All seven days, never clipped to the requested range: what was confirmed is the whole week,
    -- and a straddling week clipped to a month would read as stale.
    WITH weeks AS (
        SELECT wbc.employee,
               wbc.week_start,
               wbc.week_start + 6 AS week_end,
               wbc.minutes        AS confirmed_minutes,
               e.date_of_employment
        FROM week_balance_confirmations wbc
        JOIN employees e ON e.id = wbc.employee
        WHERE wbc.confirmed
          AND wbc.employee = ANY (in_employee_ids)
          AND wbc.week_start >= in_start_date
          AND wbc.week_start <= in_end_date
          -- accumulated_overtime_for_employee raises past the termination date rather than
          -- answering, and such a week has no capacity in the callers either.
          AND (e.termination_date IS NULL OR e.termination_date >= wbc.week_start + 6)
    ),
    -- Stands in for business_hours(), which rebuilds its generate_series and re-scans holidays on
    -- every call. The working days are the same for every employee, so expand them once and let
    -- the join below count them per week.
    workdays AS (
        SELECT d::date                     AS date,
               date_trunc('week', d)::date AS week_start
        FROM generate_series(in_start_date, in_end_date + 6, '1 day'::interval) AS d
        WHERE extract(isodow from d) <= 5
          AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = d::date)
    ),
    balances AS (
        SELECT w.employee,
               w.week_start,
               w.confirmed_minutes,
               coalesce((SELECT sum(te.minutes)
                         FROM time_entry te
                         WHERE te.employee = w.employee
                           AND te.date BETWEEN w.week_start AND w.week_end), 0)
                 -- 450 = 7.5 h * 60, the working day business_hours() hard-codes.
                 - count(wd.date) * 450
                 - coalesce((SELECT sum(po.minutes)
                             FROM paid_overtime po
                             WHERE po.employee = w.employee
                               AND po.paid_date BETWEEN w.week_start AND w.week_end), 0)
                 AS balance_minutes
        FROM weeks w
        -- Days before the hire date drop out of the count, so a week before it is 0 and one
        -- straddling it is part. date_of_employment is nullable, and a null one clips nothing.
        LEFT JOIN workdays wd ON wd.week_start = w.week_start
                             AND (w.date_of_employment IS NULL OR wd.date >= w.date_of_employment)
        GROUP BY w.employee, w.week_start, w.week_end, w.confirmed_minutes
    )
    SELECT b.employee,
           b.week_start
    FROM balances b
    WHERE b.balance_minutes >= b.confirmed_minutes
$function$;
