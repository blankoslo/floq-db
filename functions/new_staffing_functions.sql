CREATE OR REPLACE FUNCTION public.add_staffing_new(
    in_employee integer,
    in_project text,
    start_date date,
    end_date date,
    in_percentage integer DEFAULT 100
) RETURNS SETOF date
AS $$
BEGIN
    -- Add to `staffing_periods` table
    INSERT INTO staffing_periods(employee, project, start_date, end_date, percentage)
    VALUES (in_employee, in_project, start_date, end_date, in_percentage);

    -- Add to `staffing` table using available_dates
    RETURN QUERY
    SELECT * FROM insert_staffing(in_employee, in_project, start_date, end_date, in_percentage);
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION public.update_staffing_period(
    in_employee integer,
    in_project text,
    in_date date,
    in_new_start_date date DEFAULT NULL,
    in_new_end_date date DEFAULT NULL,
    in_new_percentage integer DEFAULT NULL
) RETURNS SETOF staffing_periods
AS $$
DECLARE
    old_start_date date;
    old_end_date date;
    old_percentage integer;
    new_start_date date;
    new_end_date date;
    new_percentage integer;
BEGIN
    -- Find existing staffing period
    SELECT start_date, end_date, percentage
    INTO old_start_date, old_end_date, old_percentage
    FROM staffing_periods sp
        WHERE sp.employee = in_employee
            AND sp.project = in_project
            AND in_date BETWEEN sp.start_date AND sp.end_date;

    -- Check if staffing period was found
    IF old_start_date IS NULL THEN
        RAISE EXCEPTION 'No staffing period found for employee % on project % on date %',
            in_employee, in_project, in_date;
    END IF;

    new_percentage := COALESCE(in_new_percentage, old_percentage);
    new_start_date := COALESCE(in_new_start_date, old_start_date);
    new_end_date := COALESCE(in_new_end_date, old_end_date);

    -- Update staffing by removing entries in period and adding them back
    DELETE FROM staffing
    WHERE employee = in_employee
        AND project = in_project
        AND date BETWEEN old_start_date AND old_end_date;

    PERFORM insert_staffing(in_employee, in_project, new_start_date, new_end_date, new_percentage);

    -- Update staffing_periods table, return updated row
    RETURN QUERY
        UPDATE staffing_periods
        SET start_date = new_start_date,
            end_date = new_end_date,
            percentage = new_percentage
        WHERE employee = in_employee
            AND project = in_project
            AND start_date = old_start_date
            AND end_date = old_end_date
        RETURNING *;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION public.remove_staffing_period(
    in_employee integer,
    in_project text,
    in_date date
) RETURNS SETOF staffing_periods
AS $$
DECLARE
    old_start_date date;
    old_end_date date;
BEGIN
    -- Find existing staffing period
    SELECT start_date, end_date
    INTO old_start_date, old_end_date
    FROM staffing_periods sp
        WHERE sp.employee = in_employee
            AND sp.project = in_project
            AND in_date BETWEEN sp.start_date AND sp.end_date;

    -- Check if staffing period was found
    IF old_start_date IS NULL THEN
        RAISE EXCEPTION 'No staffing period found for employee % on project % on date %',
            in_employee, in_project, in_date;
    END IF;

    DELETE FROM staffing
    WHERE employee = in_employee
        AND project = in_project
        AND date BETWEEN old_start_date AND old_end_date;

    RETURN QUERY
        DELETE FROM staffing_periods
        WHERE employee = in_employee
            AND project = in_project
            AND start_date = old_start_date
            AND end_date = old_end_date
        RETURNING *;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION public.available_dates_new(in_employee integer, start_date date, end_date date)
RETURNS TABLE(available_date date) AS
$$
BEGIN
    RETURN QUERY
    SELECT d::date AS available_date
    FROM generate_series(start_date, end_date, '1 day'::interval) d
    WHERE is_weekday(d::date)
        AND NOT is_holiday(d::date)
    EXCEPT (
        SELECT a.date AS date
        FROM absence a
        WHERE a.employee_id = in_employee
            AND a.date >= start_date
            AND a.date <= end_date
    );
END
$$ LANGUAGE plpgsql;


-- Helper functions
CREATE OR REPLACE FUNCTION public.is_weekday_new(d date)
RETURNS BOOLEAN
AS $$
BEGIN
    RETURN EXTRACT(DOW FROM d) BETWEEN 1 AND 5;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.is_employed_at_date(employee_id integer, check_date date)
RETURNS boolean
AS $$
    SELECT date_of_employment <= check_date
        AND (termination_date IS NULL OR termination_date >= check_date)
    FROM employees
    WHERE id = employee_id;
$$ LANGUAGE sql;

-- Insert a period of staffing to the staffing table
CREATE OR REPLACE FUNCTION public.insert_staffing(
    in_employee integer,
    in_project text,
    start_date date,
    end_date date,
    in_percentage integer
) RETURNS SETOF date
AS $$
BEGIN
    RETURN QUERY (
        WITH new_staffing AS (
            INSERT INTO staffing
            SELECT
                in_employee AS employee,
                in_project AS project,
                available_date AS date,
                in_percentage AS percentage
            FROM available_dates_new(in_employee, start_date, end_date)
            RETURNING date
        )
        SELECT date FROM new_staffing ORDER BY date
    );
END
$$ LANGUAGE plpgsql;
