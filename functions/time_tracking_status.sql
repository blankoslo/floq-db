CREATE OR REPLACE FUNCTION public.unavailable_hours_for_employees(start_date date, end_date date)
RETURNS TABLE(id integer, sum bigint) AS
$$
BEGIN
  RETURN QUERY (
    SELECT t.employee, SUM(t.minutes * (1 - COALESCE(a.absence_percentage, 0)))
    FROM time_entry t
    JOIN projects p ON t.project = p.id
    LEFT JOIN absence a ON t.employee = a.employee_id AND t.date = a.date
    WHERE t.date BETWEEN start_date AND end_date
    AND p.billable = 'unavailable'
    GROUP BY t.employee
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.billable_hours_for_employees(start_date date, end_date date)
RETURNS TABLE(id integer, sum bigint) AS
$$
BEGIN
  RETURN QUERY (
    SELECT t.employee, SUM(t.minutes * (1 - COALESCE(a.absence_percentage, 0)))
    FROM time_entry t
    JOIN projects p ON t.project = p.id
    LEFT JOIN absence a ON t.employee = a.employee_id AND t.date = a.date
    WHERE t.date BETWEEN start_date AND end_date
    AND p.billable = 'billable'
    GROUP BY t.employee
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.nonbillable_hours_for_employees(start_date date, end_date date)
RETURNS TABLE(id integer, sum bigint) AS
$$
BEGIN
  RETURN QUERY (
    SELECT t.employee, SUM(t.minutes * (1 - COALESCE(a.absence_percentage, 0)))
    FROM time_entry t
    JOIN projects p ON t.project = p.id
    LEFT JOIN absence a ON t.employee = a.employee_id AND t.date = a.date
    WHERE t.date BETWEEN start_date AND end_date
    AND p.billable = 'nonbillable'
    GROUP BY t.employee
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.time_tracking_status(start_date date, end_date date)
RETURNS TABLE(name text, email text, available_hours double precision, billable_hours double precision, non_billable_hours double precision, unavailable_hours double precision, unregistered_days integer, last_date date, last_created date) AS
$$
BEGIN
  RETURN QUERY (
    SELECT e.first_name || ' ' || e.last_name AS name,
           e.email,
           SUM((1 - COALESCE(a.absence_percentage, 0)) * 7.5) AS available_hours,
           COALESCE(SUM(t.billable_hours) / 60.0, 0.0)::float8 AS billable_hours,
           COALESCE(SUM(t.non_billable_hours) / 60.0, 0.0)::float8 AS non_billable_hours,
           COALESCE(SUM(t.unavailable_hours) / 60.0, 0.0)::float8 AS unavailable_hours,
           (SELECT * FROM unregistered_days(start_date, end_date, e.id) u) AS unregistered_days,
           ld.date,
           lc.created::date
    FROM employees e
    LEFT JOIN staffing s ON e.id = s.employee AND s.date BETWEEN start_date AND end_date
    LEFT JOIN absence a ON e.id = a.employee_id AND a.date BETWEEN start_date AND end_date
    LEFT JOIN (
      SELECT t.employee, 
             SUM(CASE WHEN p.billable = 'billable' THEN t.minutes ELSE 0 END) AS billable_hours,
             SUM(CASE WHEN p.billable = 'nonbillable' THEN t.minutes ELSE 0 END) AS non_billable_hours,
             SUM(CASE WHEN p.billable = 'unavailable' THEN t.minutes ELSE 0 END) AS unavailable_hours
      FROM time_entry t
      JOIN projects p ON t.project = p.id
      WHERE t.date BETWEEN start_date AND end_date
      GROUP BY t.employee
    ) t ON t.employee = e.id
    LEFT JOIN (
      SELECT DISTINCT ON(te.employee) te.employee, te.date
      FROM time_entry te
      ORDER BY te.employee, te.date DESC
    ) ld ON ld.employee = e.id
    LEFT JOIN (
      SELECT DISTINCT ON(te.employee) te.employee, te.created
      FROM time_entry te
      ORDER BY te.employee, te.created DESC
    ) lc ON lc.employee = e.id
    WHERE e.date_of_employment <= end_date AND (e.termination_date IS NULL OR e.termination_date >= start_date)
    GROUP BY e.id, ld.date, lc.created
    ORDER BY e.first_name, e.last_name
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.staffed_billable_days_for_employees(start_date date, end_date date)
RETURNS TABLE(id integer, hours double precision) AS
$$
BEGIN
  RETURN QUERY (
    SELECT s.employee, SUM(LEAST(s.staffing_percentage, 100 - COALESCE(a.absence_percentage, 0)) * 7.5) AS hours
    FROM staffing s
    JOIN projects p ON s.project = p.id
    LEFT JOIN absence a ON s.employee = a.employee_id AND s.date = a.date
    WHERE s.date BETWEEN start_date AND end_date
    AND p.billable = 'billable'
    GROUP BY s.employee
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.staffed_nonbillable_days_for_employees(start_date date, end_date date)
RETURNS TABLE(id integer, hours double precision) AS
$$
BEGIN
  RETURN QUERY (
    SELECT s.employee, SUM(LEAST(s.staffing_percentage, 100 - COALESCE(a.absence_percentage, 0)) * 7.5) AS hours
    FROM staffing s
    JOIN projects p ON s.project = p.id
    LEFT JOIN absence a ON s.employee = a.employee_id AND s.date = a.date
    WHERE s.date BETWEEN start_date AND end_date
    AND p.billable = 'nonbillable'
    GROUP BY s.employee
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.staffed_unavailable_days_for_employees(start_date date, end_date date)
RETURNS TABLE(id integer, hours double precision) AS
$$
BEGIN
  RETURN QUERY (
    SELECT s.employee, SUM(LEAST(s.staffing_percentage, 100 - COALESCE(a.absence_percentage, 0)) * 7.5) AS hours
    FROM staffing s
    JOIN projects p ON s.project = p.id
    LEFT JOIN absence a ON s.employee = a.employee_id AND s.date = a.date
    WHERE s.date BETWEEN start_date AND end_date
    AND p.billable = 'unavailable'
    GROUP BY s.employee
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.time_tracking_status_with_staffing(start_date date, end_date date)
RETURNS TABLE(name text, email text, available_hours double precision, staffed_billable_hours double precision, billable_hours double precision, staffed_nonbillable_hours double precision, non_billable_hours double precision, staffed_unavailable_hours double precision, unavailable_hours double precision, unregistered_days integer, last_date date, last_created date) AS
$$
BEGIN
  RETURN QUERY (
    SELECT e.first_name || ' ' || e.last_name AS name,
           e.email,
           SUM(CASE WHEN s.date IS NOT NULL THEN (1 - COALESCE(a.absence_percentage, 0)) * 7.5 ELSE 0 END) AS available_hours,
           coalesce(sum(t.staffed_billable_days), 0.0)::float8 AS staffed_billable_hours,
           coalesce(sum(t.billable_hours)/60.0, 0.0)::float8 AS billable_hours,
           coalesce(sum(t.staffed_nonbillable_days), 0.0)::float8 AS staffed_nonbillable_hours,
           coalesce(sum(t.non_billable_hours)/60.0, 0.0)::float8 AS non_billable_hours,
           coalesce(sum(t.staffed_unavailable_days), 0.0)::float8 AS staffed_unavailable_hours,
           coalesce(sum(t.unavailable_hours)/60.0, 0.0)::float8 AS unavailable_hours,
           (SELECT * FROM unregistered_days(start_date, end_date, e.id) u) AS unregistered_days,
           ld.date,
           lc.created::date
    FROM employees e
    LEFT JOIN (
        SELECT coalesce(uah.id, bh.id, nbh.id, sbd.id, snd.id, sud.id) AS employee_id,
               uah.sum AS unavailable_hours,
               bh.sum AS billable_hours,
               nbh.sum AS non_billable_hours,
               sbd.hours AS staffed_billable_days,
               snd.hours AS staffed_nonbillable_days,
               sud.hours AS staffed_unavailable_days
        FROM unavailable_hours_for_employees(start_date, end_date) uah
        FULL OUTER JOIN billable_hours_for_employees(start_date, end_date) bh ON uah.id = bh.id
        FULL OUTER JOIN nonbillable_hours_for_employees(start_date, end_date) nbh ON uah.id = nbh.id
        FULL OUTER JOIN staffed_billable_days_for_employees(start_date, end_date) sbd ON uah.id = sbd.id
        FULL OUTER JOIN staffed_nonbillable_days_for_employees(start_date, end_date) snd ON uah.id = snd.id
        FULL OUTER JOIN staffed_unavailable_days_for_employees(start_date, end_date) sud ON uah.id = sud.id
    ) AS t ON t.employee_id = e.id
    LEFT JOIN (
      SELECT DISTINCT ON(te.employee) te.employee, te.date
      FROM time_entry te
      ORDER BY te.employee, te.date DESC
    ) ld ON ld.employee = e.id
    LEFT JOIN (
      SELECT DISTINCT ON(te.employee) te.employee, te.created
      FROM time_entry te
      ORDER BY te.employee, te.created DESC
    ) lc ON lc.employee = e.id
    WHERE e.date_of_employment <= end_date AND (e.termination_date IS NULL OR e.termination_date >= start_date)
    GROUP BY e.id, ld.date, lc.created
    ORDER BY e.first_name, e.last_name
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.fg_for_employee(emp_id integer, start_date date, end_date date)
RETURNS TABLE(available_hours double precision, billable_hours double precision) AS
$$
BEGIN
  RETURN QUERY (
    SELECT 
      SUM(CASE WHEN s.date IS NOT NULL THEN LEAST(s.staffing_percentage, 100 - COALESCE(a.absence_percentage, 0)) * 7.5 ELSE 0 END) AS available_hours,
      SUM(CASE WHEN s.date IS NOT NULL AND p.billable = 'billable' THEN LEAST(s.staffing_percentage, 100 - COALESCE(a.absence_percentage, 0)) * 7.5 ELSE 0 END) AS billable_hours
    FROM employees e
    LEFT JOIN staffing s ON e.id = s.employee AND s.date BETWEEN start_date AND end_date
    LEFT JOIN absence a ON e.id = a.employee_id AND a.date = s.date
    LEFT JOIN projects p ON s.project = p.id
    WHERE e.id = emp_id
    GROUP BY e.id
  );
END
$$ LANGUAGE plpgsql;
