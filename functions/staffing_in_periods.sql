-- Staff all available dates within a range.
CREATE OR REPLACE FUNCTION public.insert_staffing(
    in_employee integer,
    in_project text,
    start_date date,
    end_date date,
    percentage integer DEFAULT 100
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
                percentage AS percentage
            FROM available_dates_new(in_employee, start_date, end_date)
            ON CONFLICT (employee, project, date) DO NOTHING
            RETURNING date
        )
        SELECT date FROM new_staffing ORDER BY date
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.update_staffing_period(
    in_employee integer,
    in_project text,
    start_date date,
    end_date date,
    percentage integer DEFAULT 100
) RETURNS SETOF date
AS $$
BEGIN
    DELETE FROM staffing
    WHERE employee = in_employee
        AND project = in_project
        AND date BETWEEN start_date AND end_date;

    RETURN QUERY SELECT * FROM insert_staffing(in_employee, in_project, start_date, end_date, percentage);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.remove_staffing(
    in_employee integer,
    in_project text,
    start_date date,
    end_date date DEFAULT NULL
) RETURNS SETOF date
AS $$
BEGIN
    RETURN QUERY (
        WITH deleted_rows AS (
            DELETE FROM staffing
            WHERE employee = in_employee
                AND project = in_project
                AND date >= start_date
                AND (end_date IS NULL OR date <= end_date) -- end_date = null: delete everything since start_date
            RETURNING date
        )
        SELECT date FROM deleted_rows ORDER BY date
    );
END
$$ LANGUAGE plpgsql;


-- TODO: Check unavailable dates?
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
