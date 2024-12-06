BEGIN;


CREATE OR REPLACE FUNCTION accumulated_staffing_hours(from_date date, to_date date)
RETURNS TABLE (available_hours numeric, billable_hours numeric, nonbillable_hours numeric, unavailable_hours numeric) AS
$$
BEGIN
  RETURN QUERY (
  WITH daily_hours AS (
    SELECT
      date,
      employee,
      SUM(CASE WHEN p.billable = 'billable' THEN s.percentage * 0.075 ELSE 0 END) AS billable,
      SUM(CASE WHEN p.billable = 'nonbillable' THEN s.percentage * 0.075 ELSE 0 END) AS nonbillable,
      SUM(CASE WHEN p.billable = 'unavailable' THEN s.percentage * 0.075 ELSE 0 END) AS unavailable
    FROM staffing s
    JOIN projects p ON s.project = p.id
    WHERE s.date BETWEEN from_date AND to_date
    GROUP BY date,employee
  ),
  absence_hours AS (
    SELECT
      date,
      employee_id AS employee,
      SUM(CASE WHEN ar.billable = 'unavailable' :: time_status THEN a.percentage * 0.075 ELSE 0 END) as unavailable,
      SUM(CASE WHEN ar.billable = 'nonbillable' :: time_status THEN a.percentage * 0.075 ELSE 0 END) as nonbillable
      FROM absence a
      JOIN absence_reasons ar ON ar.id = a.reason
      WHERE a.date BETWEEN from_date AND to_date
      GROUP BY date, employee_id
  ),
  total_hours AS (
    SELECT
      COALESCE(d.date, a.date) AS date,
      COALESCE(d.employee, a.employee) AS employee,
      COALESCE(d.billable, 0) AS billable,
      COALESCE(d.nonbillable, 0) + COALESCE(a.nonbillable, 0) AS nonbillable,
      COALESCE(d.unavailable, 0) + COALESCE(a.unavailable, 0) AS unavailable
    FROM daily_hours d
    FULL OUTER JOIN absence_hours a
      ON d.date = a.date AND d.employee = a.employee
  )
  SELECT
    (SELECT SUM(available_hours) FROM available_hours_per_employee(from_date, to_date)) AS available_hours,
    SUM(billable) AS billable_hours,
    SUM(nonbillable) AS nonbillable_hours,
    SUM(unavailable) AS unavailable_hours
  FROM total_hours
  );
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION available_hours_per_employee(from_date date, to_date date)
RETURNS TABLE (employee_id integer, avail_hours numeric) AS
$$
BEGIN
  RETURN QUERY (
    WITH possible_work_days AS (
      SELECT
        e.id AS employee_id,
        generate_series::DATE AS work_day
      FROM employees e
      CROSS JOIN generate_series(from_date, to_date, '1 day'::interval)
      WHERE is_weekday(generate_series::DATE)
        AND NOT is_holiday(generate_series::DATE)
        AND generate_series::DATE >= e.date_of_employment
        AND (e.termination_date IS NULL OR generate_series::DATE <= e.termination_date)
    ),
    daily_availability AS (
    SELECT
      days.employee_id,
      days.work_day,
      COALESCE(s.percentage, 0) AS staffing_percentage,
      COALESCE(a.percentage, 0) AS absence_percentage
    FROM possible_work_days days
    LEFT JOIN (
          SELECT employee, date, SUM(percentage) AS percentage
          FROM staffing s
          JOIN projects p ON p.id = s.project
          WHERE p.billable = 'unavailable'
          GROUP BY employee, date
      ) s ON days.employee_id = s.employee AND days.work_day = s.date
      LEFT JOIN(
          SELECT employee_id, date, SUM(percentage) AS percentage
          FROM absence a
          JOIN absence_reasons ar ON ar.id = a.reason
          WHERE ar.billable = 'unavailable'
          GROUP BY employee_id, date
      ) a ON days.employee_id = a.employee_id AND days.work_day = a.date
    )
    SELECT
      employee_id,
      GREATEST(100 - staffing_percentage - absence_percentage, 0) * 0.075 AS available_hours
    FROM daily_percentages
  );
END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION staffing_and_billing_overview(in_from_date date, in_to_date date)
RETURNS TABLE (
  year int,
  week int,
  from_date date,
  to_date date,
  available_hours numeric,
  billable_hours numeric,
  planned_fg numeric,
  actual_available_hours double precision,
  actual_billable_hours numeric,
  actual_fg double precision,
  deviation_available_hours double precision,
  deviation_billable_hours numeric,
  deviation_fg numeric
) AS
$$
BEGIN
  RETURN QUERY (

SELECT
  x.year,
  x.week,
  x.from_date,
  x.to_date,
  planned.available_hours,
  planned.billable_hours,
  100*(planned.billable_hours / planned.available_hours)                              AS planned_fg,
  actual.sum_available_hours                                                          AS actual_available_hours,
  actual.sum_billable_hours                                                           AS actual_billable_hours,
  100*(actual.sum_billable_hours / actual.sum_available_hours)                        AS actual_fg,
  actual.sum_available_hours - planned.available_hours                                AS deviation_available_hours,
  actual.sum_billable_hours - planned.billable_hours                                  AS deviation_billable_hours,
  100*((actual.sum_billable_hours - planned.billable_hours)/ planned.available_hours) AS deviation_fg
FROM
  (SELECT
     tt.year                             AS year,
     tt.week                             AS week,
     (SELECT min(date)
      FROM week_dates(tt.year, tt.week)) AS from_date,
     (SELECT max(date)
      FROM week_dates(tt.year, tt.week)) AS to_date

   FROM
     (
       SELECT
         EXTRACT(YEAR FROM dd) :: integer AS year,
         EXTRACT(WEEK FROM dd) :: integer AS week
       FROM
         generate_series(in_from_date, in_to_date, '1 week' :: interval) dd
     ) tt
  ) x
  LEFT OUTER JOIN reporting_visibility v ON (v.year = x.year AND v.week = x.week),
  accumulated_staffing_hours(x.from_date, x.to_date) planned,
  accumulated_billed_hours(x.from_date, x.to_date) actual

  );
END
$$ LANGUAGE plpgsql;
