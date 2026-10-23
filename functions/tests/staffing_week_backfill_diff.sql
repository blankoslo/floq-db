-- Dry run for the backfill_staffing_week sqitch change: what copying staffing into
-- staffing_week would change, without writing anything. Run it against a copy of
-- prod before deploying the change.
--     psql -d floq -f functions/tests/staffing_week_backfill_diff.sql
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.

BEGIN;

CREATE TEMP VIEW staffing_working_day AS
SELECT e.id AS employee, day::date AS date
FROM employees e
CROSS JOIN generate_series(
    (SELECT date_trunc('week', MIN(date))::date FROM staffing),
    (SELECT MAX(date) FROM staffing),
    interval '1 day') AS day
WHERE EXTRACT(ISODOW FROM day) < 6
  AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = day::date)
  AND day::date >= e.date_of_employment
  AND (e.termination_date IS NULL OR day::date <= e.termination_date);

CREATE TEMP VIEW staffing_fold AS
SELECT booked.employee,
       booked.project,
       booked.week_start,
       booked.points,
       COUNT(wd.date)::integer AS working_days,
       CASE WHEN COUNT(wd.date) > 0
            THEN LEAST(100, ROUND(booked.points::numeric / COUNT(wd.date), 4)) END AS percentage,
       EXISTS (SELECT 1 FROM staffing_week sw
                WHERE sw.employee = booked.employee
                  AND sw.project = booked.project
                  AND sw.week_start = booked.week_start) AS already_copied
FROM (
    SELECT employee, project, date_trunc('week', date)::date AS week_start, SUM(percentage) AS points
    FROM staffing
    GROUP BY employee, project, date_trunc('week', date)
    HAVING SUM(percentage) > 0
) booked
LEFT JOIN staffing_working_day wd
       ON wd.employee = booked.employee
      AND wd.date BETWEEN booked.week_start AND booked.week_start + 4
GROUP BY booked.employee, booked.project, booked.week_start, booked.points;

\echo
\echo '== Summary =='
SELECT COUNT(*) FILTER (WHERE NOT already_copied AND working_days > 0)        AS weeks_to_copy,
       COUNT(*) FILTER (WHERE already_copied)                                 AS weeks_already_copied,
       COUNT(*) FILTER (WHERE working_days = 0)                               AS weeks_without_working_days,
       COUNT(*) FILTER (WHERE working_days > 0 AND points > 100 * working_days) AS weeks_capped_at_100
FROM staffing_fold;

\echo
\echo '== Capped at 100: more points than the week has working days =='
SELECT employee, project, to_char(week_start, 'IYYY-IW') AS week, points, working_days,
       points / 100.0 - working_days AS days_lost
FROM staffing_fold
WHERE working_days > 0 AND points > 100 * working_days
ORDER BY week_start DESC, employee, project;

\echo
\echo '== Not copied: no working days (holidays, or outside employment) =='
SELECT f.employee, f.project, to_char(f.week_start, 'IYYY-IW') AS week, f.points,
       e.date_of_employment, e.termination_date
FROM staffing_fold f
JOIN employees e ON e.id = f.employee
WHERE f.working_days = 0
ORDER BY f.week_start DESC, f.employee, f.project;

\echo
\echo '== Hours per employee and month that move by a quarter hour or more =='
\echo '   before: points on working days, as the platform reports count them today'
\echo '   after:  the copied percentage on each working day'
WITH before AS (
    SELECT s.employee, date_trunc('month', s.date)::date AS month, SUM(s.percentage) * 0.075 AS hours
    FROM staffing s
    JOIN staffing_working_day wd ON wd.employee = s.employee AND wd.date = s.date
    GROUP BY 1, 2
),
after AS (
    SELECT f.employee, date_trunc('month', wd.date)::date AS month, SUM(f.percentage) * 0.075 AS hours
    FROM staffing_fold f
    JOIN staffing_working_day wd
      ON wd.employee = f.employee AND wd.date BETWEEN f.week_start AND f.week_start + 4
    WHERE f.percentage IS NOT NULL
    GROUP BY 1, 2
)
SELECT COALESCE(b.employee, a.employee) AS employee,
       to_char(COALESCE(b.month, a.month), 'YYYY-MM') AS month,
       ROUND(COALESCE(b.hours, 0), 2) AS hours_before,
       ROUND(COALESCE(a.hours, 0), 2) AS hours_after,
       ROUND(COALESCE(a.hours, 0) - COALESCE(b.hours, 0), 2) AS difference
FROM before b
FULL JOIN after a ON a.employee = b.employee AND a.month = b.month
WHERE ABS(COALESCE(a.hours, 0) - COALESCE(b.hours, 0)) >= 0.25
ORDER BY month DESC, employee;

ROLLBACK;
