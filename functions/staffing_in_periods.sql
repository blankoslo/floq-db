-- Staff all available dates within a range.
CREATE OR REPLACE FUNCTION public.insert_staffing(
    in_employee integer,
    in_project text,
    start_date date,
    end_date date,
    percentage integer DEFAULT 100
) RETURNS SETOF date
AS $$
DECLARE
    is_absence BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM absence_reasons
        WHERE id = in_project
    ) INTO is_absence;

    IF is_absence THEN
        RAISE EXCEPTION 'Cannot insert absence into the staffing table: "%"', in_project;
    END IF;

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

CREATE OR REPLACE FUNCTION public.upsert_staffing(
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


CREATE OR REPLACE FUNCTION public.available_dates_new(start_date date, end_date date)
RETURNS TABLE(available_date date) AS
$$
BEGIN
    RETURN QUERY
    SELECT d::date AS available_date
    FROM generate_series(start_date, end_date, '1 day'::interval) d
    WHERE is_weekday(d::date) AND NOT is_holiday(d::date);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.availability_percentage(
    start_date date,
    end_date date,
    in_employee integer DEFAULT NULL
)
RETURNS DECIMAL(5,2) AS
$$
DECLARE
    total_working_days INTEGER;
    total_possible_percentage INTEGER;
    unavailable_percentage INTEGER;
    available_percentage INTEGER;
    result_percentage DECIMAL(5,2);
    active_employee_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO total_working_days
    FROM available_dates_new(start_date, end_date);

    -- Start with 100% per workable day
    total_possible_percentage := total_working_days * 100;

    IF in_employee IS NOT NULL THEN
        -- Single employee


        -- Calculate unavailable percentage (absence marked as unavailable)
        SELECT COALESCE(SUM(100), 0)
        INTO unavailable_percentage
        FROM absence a
        JOIN absence_reasons ar ON a.reason = ar.id
        WHERE a.employee_id = in_employee
            AND a.date BETWEEN start_date AND end_date
            AND ar.billable = 'unavailable';
    ELSE
        -- All employees
        SELECT COUNT(*)
        INTO active_employee_count
        FROM get_employees_in_dates(start_date, end_date);

        -- Start with 100% per workable day
        total_possible_percentage := total_possible_percentage * active_employee_count;

        SELECT COALESCE(SUM(100), 0)
        INTO unavailable_percentage
        FROM absence a
        JOIN absence_reasons ar ON a.reason = ar.id
        WHERE a.employee_id IN (
            SELECT employee_id FROM get_employees_in_dates(start_date, end_date)
        )
        AND a.date BETWEEN start_date AND end_date
        AND ar.billable = 'unavailable';
    END IF;

    -- Calculate available percentage: total possible - unavailable
    available_percentage := total_possible_percentage - unavailable_percentage;

    -- Calculate final percentage
    IF total_possible_percentage = 0 THEN
        RETURN 0.00;
    ELSE
        result_percentage := (available_percentage::DECIMAL / total_possible_percentage::DECIMAL) * 100;
        RETURN GREATEST(0.00, result_percentage);
    END IF;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.weekly_availability_json(start_date date, end_date date)
RETURNS jsonb AS
$$
DECLARE
    cur_week_start date;
    period_end date;
    str_week text;
    result jsonb := '{}'::jsonb;
    availability  DECIMAL(5,2);
BEGIN
    cur_week_start := DATE_TRUNC('week', start_date);
    period_end := DATE_TRUNC('week', end_date);

    WHILE cur_week_start <= period_end LOOP
        str_week := TO_CHAR(cur_week_start, 'IYYY-IW');

        availability := availability_percentage(cur_week_start, (cur_week_start + INTERVAL '7 days')::date, NULL);
        result := result || jsonb_build_object(str_week, ROUND(availability::numeric, 1));

        cur_week_start := cur_week_start + INTERVAL '7 days';
    END LOOP;
    RETURN result;
END
$$ LANGUAGE plpgsql;
