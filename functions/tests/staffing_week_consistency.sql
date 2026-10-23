-- Whether staffing and staffing_week still agree, week by week. Run it after the
-- backfill_staffing_week sqitch change and keep running it until staffing is dropped:
-- floq-platform writes both on every save, so any row here means something wrote
-- only one of them.
--     psql -d floq -f functions/tests/staffing_week_consistency.sql
-- NOT deployed: functions/deploy.sh globs functions/*.sql and does not recurse.
--
-- Expected rows: weeks staffing holds more points than the week has working days
-- (staffing_week caps at 100), and weeks with no working days (no staffing_week row).
-- The difference column says which.

BEGIN;

WITH booked AS (
    SELECT employee, project, date_trunc('week', date)::date AS week_start, SUM(percentage) AS points
    FROM staffing
    GROUP BY employee, project, date_trunc('week', date)
    HAVING SUM(percentage) > 0
),
weeks AS (
    SELECT COALESCE(b.employee, sw.employee)     AS employee,
           COALESCE(b.project, sw.project)       AS project,
           COALESCE(b.week_start, sw.week_start) AS week_start,
           b.points,
           sw.percentage
    FROM booked b
    FULL JOIN staffing_week sw
           ON sw.employee = b.employee AND sw.project = b.project AND sw.week_start = b.week_start
),
measured AS (
    SELECT w.*,
           (SELECT COUNT(*)
              FROM generate_series(w.week_start, w.week_start + 4, interval '1 day') AS day
              JOIN employees e ON e.id = w.employee
             WHERE NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = day::date)
               AND day::date >= e.date_of_employment
               AND (e.termination_date IS NULL OR day::date <= e.termination_date))::integer AS working_days
    FROM weeks w
)
SELECT employee,
       project,
       to_char(week_start, 'IYYY-IW') AS week,
       points,
       percentage,
       working_days,
       CASE
           WHEN percentage IS NULL AND working_days = 0                 THEN 'expected: no working days'
           WHEN percentage IS NULL                                      THEN 'MISSING in staffing_week'
           WHEN points IS NULL                                          THEN 'MISSING in staffing'
           WHEN percentage = 100 AND points > 100 * working_days        THEN 'expected: capped at 100'
           ELSE 'DIFFERENT'
       END AS difference
FROM measured
WHERE points IS DISTINCT FROM ROUND(percentage * working_days)::integer
ORDER BY (CASE WHEN percentage IS NULL AND working_days = 0 THEN 1
               WHEN percentage = 100 AND points > 100 * working_days THEN 1
               ELSE 0 END),
         week_start DESC, employee, project;

ROLLBACK;
