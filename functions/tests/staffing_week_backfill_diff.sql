-- Dry run for the backfill_staffing_week sqitch change: what copying staffing into
-- staffing_week would change. Writes only temporary tables, which the ROLLBACK at
-- the end drops, as does losing the connection.
--     psql -d floq -f functions/tests/staffing_week_backfill_diff.sql
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.

BEGIN;

CREATE TEMP TABLE booked AS
SELECT employee, project, date_trunc('week', date)::date AS week_start, SUM(percentage) AS points
FROM staffing
GROUP BY employee, project, date_trunc('week', date)
HAVING SUM(percentage) > 0;

-- The working days of each booked week, the same five-day test the backfill makes.
CREATE TEMP TABLE booked_day AS
SELECT b.employee, b.project, b.week_start, day::date AS date
FROM booked b
JOIN employees e ON e.id = b.employee
CROSS JOIN LATERAL generate_series(b.week_start, b.week_start + 4, interval '1 day') AS day
WHERE NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = day::date)
  AND day::date >= e.date_of_employment
  AND (e.termination_date IS NULL OR day::date <= e.termination_date);

CREATE TEMP TABLE fold AS
SELECT b.employee,
       b.project,
       b.week_start,
       b.points,
       COUNT(bd.date)::integer AS working_days,
       CASE WHEN COUNT(bd.date) > 0
            THEN LEAST(100, ROUND(b.points::numeric / COUNT(bd.date), 4)) END AS percentage,
       sw.employee IS NOT NULL AS already_copied
FROM booked b
LEFT JOIN booked_day bd
       ON bd.employee = b.employee AND bd.project = b.project AND bd.week_start = b.week_start
LEFT JOIN staffing_week sw
       ON sw.employee = b.employee AND sw.project = b.project AND sw.week_start = b.week_start
GROUP BY b.employee, b.project, b.week_start, b.points, sw.employee;

ANALYZE booked_day;
ANALYZE fold;

\echo
\echo '== Summary =='
SELECT COUNT(*) FILTER (WHERE NOT already_copied AND working_days > 0)          AS weeks_to_copy,
       COUNT(*) FILTER (WHERE already_copied)                                   AS weeks_already_copied,
       COUNT(*) FILTER (WHERE working_days = 0)                                 AS weeks_without_working_days,
       COUNT(*) FILTER (WHERE working_days > 0 AND points > 100 * working_days) AS weeks_capped_at_100
FROM fold;

\echo
\echo '== Capped at 100: more points than the week has working days =='
SELECT employee, project, to_char(week_start, 'IYYY-IW') AS week, points, working_days,
       points / 100.0 - working_days AS days_on_non_working_days
FROM fold
WHERE working_days > 0 AND points > 100 * working_days
ORDER BY week_start DESC, employee, project;

\echo
\echo '== Not copied: no working days (holidays, or outside employment) =='
SELECT f.employee, f.project, to_char(f.week_start, 'IYYY-IW') AS week, f.points,
       e.date_of_employment, e.termination_date
FROM fold f
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
    JOIN employees e ON e.id = s.employee
    WHERE EXTRACT(ISODOW FROM s.date) < 6
      AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = s.date)
      AND s.date >= e.date_of_employment
      AND (e.termination_date IS NULL OR s.date <= e.termination_date)
    GROUP BY 1, 2
),
after AS (
    SELECT bd.employee, date_trunc('month', bd.date)::date AS month, SUM(f.percentage) * 0.075 AS hours
    FROM booked_day bd
    JOIN fold f ON f.employee = bd.employee AND f.project = bd.project AND f.week_start = bd.week_start
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
