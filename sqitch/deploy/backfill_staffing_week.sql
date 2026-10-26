-- Deploy floq:backfill_staffing_week to pg
-- requires: add_staffing_week
-- requires: staffing_table
-- requires: employees_table
-- requires: holidays_table
-- requires: absence_table

BEGIN;

-- Copies every week of the per-date staffing table into staffing_week. Weeks saved
-- since floq-platform started writing both tables already have their row, which is
-- exact where this one would be rounded from points, so those are left alone and
-- this can be re-run.
--
-- A week's percentage is its points over its working days - weekdays that are not
-- public holidays, inside employment - capped at 100. That is the rule the platform
-- writes with (StaffedWeekRule): 3 days in a week with two holidays is 100. Nobody
-- without a date_of_employment has working days, and a week with none gets no row.
-- Absence codes are left behind: they belong in absence, and staffing_week refuses
-- them.
INSERT INTO staffing_week (employee, week_start, project, percentage)
SELECT booked.employee,
       booked.week_start,
       booked.project,
       LEAST(100, ROUND(booked.points::numeric / working.days, 4))
FROM (
    SELECT employee, project, date_trunc('week', date)::date AS week_start, SUM(percentage) AS points
    FROM staffing
    WHERE NOT is_absence_reason(project)
    GROUP BY employee, project, date_trunc('week', date)
) booked
JOIN employees e ON e.id = booked.employee
CROSS JOIN LATERAL (
    SELECT COUNT(*) AS days
    FROM generate_series(booked.week_start, booked.week_start + 4, interval '1 day') AS day
    WHERE NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = day::date)
      AND day::date >= e.date_of_employment
      AND (e.termination_date IS NULL OR day::date <= e.termination_date)
) working
WHERE booked.points > 0
  AND working.days > 0
ON CONFLICT (employee, week_start, project) DO NOTHING;

COMMIT;
