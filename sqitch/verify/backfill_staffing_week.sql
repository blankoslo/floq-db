-- Verify floq:backfill_staffing_week on pg

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM (
            SELECT employee, project, date_trunc('week', date)::date AS week_start
            FROM staffing
            GROUP BY employee, project, date_trunc('week', date)
            HAVING SUM(percentage) > 0
        ) booked
        JOIN employees e ON e.id = booked.employee
        WHERE EXISTS (
                  SELECT 1
                  FROM generate_series(booked.week_start, booked.week_start + 4, interval '1 day') AS day
                  WHERE NOT EXISTS (SELECT 1 FROM holidays h WHERE h.date = day::date)
                    AND day::date >= e.date_of_employment
                    AND (e.termination_date IS NULL OR day::date <= e.termination_date))
          AND NOT EXISTS (
                  SELECT 1
                  FROM staffing_week sw
                  WHERE sw.employee = booked.employee
                    AND sw.project = booked.project
                    AND sw.week_start = booked.week_start)
    ) THEN
        RAISE EXCEPTION 'A week booked in staffing with working days has no staffing_week row';
    END IF;
END $$;
