BEGIN;


CREATE OR REPLACE FUNCTION accumulated_staffing_hours(from_date date, to_date date)
RETURNS TABLE (available_hours numeric, billable_hours numeric, nonbillable_hours numeric, unavailable_hours numeric) AS
$$
BEGIN
  RETURN QUERY (
SELECT
    (SELECT COUNT(work_day) * 7.5 as avail_hours FROM possible_work_dates_per_employee(from_date, to_date)) AS available_hours,
    SUM(CASE WHEN staff.billable = 'billable' :: time_status THEN 1 ELSE 0 END) * 7.5 AS billable_hours,
    SUM(CASE WHEN staff.billable = 'nonbillable' :: time_status THEN 1 ELSE 0 END) * 7.5 AS nonbillable_hours,
    SUM(CASE WHEN staff.billable = 'unavailable' :: time_status THEN 1 ELSE 0 END) * 7.5 AS unavailable_hours
  FROM (SELECT * FROM staffing
    JOIN projects ON (staffing.project = projects.id)
    WHERE staffing.date BETWEEN from_date AND to_date) AS staff

  );
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION possible_work_dates_per_employee(from_date date, to_date date)
RETURNS TABLE (employee_id integer, work_day date) AS
$$
BEGIN
  RETURN QUERY (
    SELECT
      x.emp_id,
      x.work_day
    FROM
      (SELECT
         e.id                    AS emp_id,
         e.first_name,
         e.last_name,
         generate_series :: DATE AS work_day
       FROM employees e
         CROSS JOIN
           generate_series(from_date, to_date, '1 day' :: interval)
      ) AS x
    WHERE
      is_possible_work_day(x.emp_id, x.work_day)
  );
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION is_possible_work_day(in_employee_id numeric, in_date date)
  RETURNS BOOLEAN AS
$$
BEGIN
  RETURN (
    is_weekday(in_date)
    AND NOT is_holiday(in_date)
    AND NOT EXISTS(SELECT *
                   FROM employees e
                   WHERE e.id = in_employee_id AND e.termination_date < in_date)
    AND EXISTS(SELECT *
               FROM employees e
               WHERE e.id = in_employee_id AND e.date_of_employment <= in_date)
    AND (
      NOT EXISTS(SELECT *
                 FROM staffing s
                 WHERE s.employee = in_employee_id AND s.date = in_date)
      OR EXISTS(SELECT *
                FROM staffing s
                  JOIN projects p ON s.project = p.id
                WHERE s.employee = in_employee_id AND s.date = in_date AND p.billable != 'unavailable' :: time_status)
    )
    AND NOT EXISTS(SELECT *
                   FROM absence a
                     JOIN absence_reasons ar ON (ar.id = a.reason)
                   WHERE
                     a.employee_id = in_employee_id AND a.date = in_date AND ar.billable = 'unavailable' :: time_status)
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
  actual_available_hours numeric,
  actual_billable_hours numeric,
  actual_fg numeric,
  deviation_available_hours numeric,
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


CREATE OR REPLACE FUNCTION accumulated_billed_hours(from_date date, to_date date)
RETURNS TABLE (sum_available_hours numeric, sum_billable_hours numeric) AS
$$
BEGIN
  RETURN QUERY (
    SELECT
         SUM(available_hours) :: numeric AS sum_available_hours,
         SUM(billable_hours)  :: numeric AS sum_billable_hours
       FROM time_tracking_status(from_date, to_date)
      );
END
$$ LANGUAGE plpgsql;

COMMIT;
