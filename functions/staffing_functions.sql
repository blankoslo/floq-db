-- Deploy floq:absence_view to pg
-- requires: norwegian_holidays_to_2018
-- requires: staffing_table
-- requires: employees_table

BEGIN;

CREATE OR REPLACE FUNCTION is_holiday(d date)
        RETURNS boolean AS
$$
BEGIN
  RETURN EXISTS (SELECT * FROM public.holidays WHERE holidays.date = d);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION is_weekday(d date)
        RETURNS boolean AS
$$
BEGIN
  RETURN NOT (    EXTRACT(dow FROM d) = 0
               OR EXTRACT(dow FROM d) = 6
             );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION week_dates(in_year integer, in_week integer)
RETURNS TABLE ( date date ) AS
$$
BEGIN
  RETURN QUERY SELECT date_trunc('week', (in_year::text || '-1-4')::timestamp)::date
    + 7 * (in_week - 1)  -- fix off-by-one
    + generate_series (0, 6);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION available_dates(e integer, in_year integer, in_week integer)
RETURNS TABLE ( available_date date ) AS
$$
BEGIN
  RETURN QUERY
  SELECT date AS available_date
    FROM week_dates(in_year, in_week)
   WHERE is_weekday(date) AND NOT is_holiday(date)
  EXCEPT ( SELECT staffing.date AS date FROM staffing WHERE employee = e
            UNION
           SELECT absence.date AS date FROM absence WHERE employee_id = e
         );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fix_staffing_on_weekends_and_holidays()
RETURNS TABLE (employee integer, year integer, week integer, count integer, project text) AS
$$
BEGIN
  RETURN QUERY (
    WITH move_candidates AS (
        SELECT staffing.employee,
               EXTRACT(YEAR FROM staffing.date) AS year,
               EXTRACT(WEEK FROM staffing.date) AS week,
               COUNT(staffing.date) AS count,
               staffing.project
          FROM staffing
         WHERE is_holiday(staffing.date) OR NOT is_weekday(staffing.date)
      GROUP BY staffing.employee, year, week, staffing.project
      ), reassigned_candidates AS (
        SELECT * FROM move_candidates s1 LEFT JOIN LATERAL (
          SELECT available_date
            FROM available_dates(s1.employee::integer, s1.year::integer, s1.week::integer)
           LIMIT s1.count
        ) s2 ON true
      ), moved_candidates AS (
        INSERT INTO staffing (employee, date, project)
          ( SELECT reassigned_candidates.employee,
                   available_date AS date,
                   reassigned_candidates.project
              FROM reassigned_candidates
             WHERE available_date IS NOT NULL
          )
      ), old_candidates AS (
        DELETE FROM staffing
              WHERE is_holiday(staffing.date) OR NOT is_weekday(staffing.date)
      )
    SELECT t.employee,
           t.year  ::integer,
           t.week  ::integer,
           t.count ::integer,
           t.project
      FROM reassigned_candidates t
     WHERE t.available_date IS NULL
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION is_date_in_week(in_date date, in_year integer, in_week integer)
RETURNS boolean AS
$$
BEGIN
  RETURN (    EXTRACT(YEAR FROM in_date) = in_year
          AND EXTRACT(WEEK FROM in_date) = in_week
         );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_staffing(
  in_employee integer,
  in_project text,
  in_year integer,
  in_week integer,
  in_days integer
)
RETURNS SETOF date AS
$$
BEGIN
  RETURN QUERY (
    WITH new_staffing AS (
      INSERT INTO staffing (employee, date, project)
        ( SELECT in_employee AS employee,
                 available_date AS date,
                 in_project AS project
            FROM available_dates(in_employee, in_year, in_week)
        ORDER BY date ASC
           LIMIT in_days
        )
        RETURNING date
      )
      SELECT date FROM new_staffing
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION remove_staffing(
  in_employee integer,
  in_project text,
  in_year integer,
  in_week integer,
  in_days integer
)
RETURNS SETOF date AS
$$
BEGIN
  RETURN QUERY (
    WITH old_staffing AS (
      DELETE FROM staffing
            WHERE employee = in_employee
              AND project = in_project
              AND date IN ( SELECT date FROM staffing
                             WHERE employee = in_employee
                               AND project = in_project
                               AND is_date_in_week(date, in_year, in_week)
                          ORDER BY date DESC
                             LIMIT in_days
                          )
        RETURNING date
      )
      SELECT date FROM old_staffing
  );
END
$$ LANGUAGE plpgsql;

COMMIT;

CREATE OR REPLACE FUNCTION employees_on_projects(from_date date, to_date date)
RETURNS TABLE (customer_id text, customer_name text, first_name text, last_name text, id int, emoji text) AS
$$
BEGIN
return query (
SELECT
  customers.id as customer,
  customers.name,
  employees.first_name,
  employees.last_name,
  employees.id,
  employees.emoji::text
FROM employees
  JOIN staffing ON staffing.employee = employees.id
  JOIN projects ON staffing.project = projects.id
  JOIN customers ON projects.customer = customers.id
WHERE
  projects.billable = 'billable' AND
  staffing.date > from_date  AND
  staffing.date < to_date
GROUP BY
  employees.id,
  customers.id
);
END
$$ language plpgsql;
