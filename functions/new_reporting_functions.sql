CREATE OR REPLACE FUNCTION possible_work_days_per_employee(from_date date, to_date date)
RETURNS TABLE (employee_id integer, work_day date) AS
$$
    SELECT
        e.id AS employee_id,
        d::date AS work_day
    FROM employees e
    CROSS JOIN generate_series(
        GREATEST(e.date_of_employment, from_date),
        LEAST(COALESCE(e.termination_date, to_date), to_date),
        '1 day'::interval
    ) d
    WHERE e.date_of_employment <= to_date
        AND (e.termination_date IS NULL OR e.termination_date >= from_date)
        AND is_weekday_new(d::date)
        AND NOT is_holiday(d::date)
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION available_hours(from_date date, to_date date)
RETURNS numeric AS
$$
    WITH work_days AS (
        SELECT employee_id, work_day
        FROM possible_work_days_per_employee(from_date, to_date)
    ),
    employee_daily_hours AS (
        SELECT
            wd.employee_id,
            wd.work_day,
            COALESCE(SUM(s.percentage), 100) * 7.5 / 100.0 AS hours -- No staffing = 100% available
        FROM work_days wd
        LEFT JOIN staffing s ON s.employee = wd.employee_id AND s.date = wd.work_day
        LEFT JOIN absence a ON a.employee_id = wd.employee_id AND a.date = wd.work_day
        LEFT JOIN absence_reasons ar ON ar.id = a.reason
        WHERE ar.billable IS NULL OR ar.billable != 'unavailable'
        GROUP BY wd.employee_id, wd.work_day
    )
    SELECT SUM(hours)
    FROM employee_daily_hours;
$$ LANGUAGE sql;


CREATE OR REPLACE FUNCTION available_hours_for_employee(in_employee_id integer, from_date date, to_date date)
RETURNS numeric AS
$$
    WITH employee_daily_hours AS (
        SELECT
            wd.work_day,
            COALESCE(SUM(s.percentage), 100) * 7.5 / 100.0 AS hours -- No staffing = 100% available
        FROM possible_work_days_per_employee(from_date, to_date) wd
        LEFT JOIN staffing s ON s.employee = wd.employee_id AND s.date = wd.work_day
        LEFT JOIN absence a ON a.employee_id = wd.employee_id AND a.date = wd.work_day
        LEFT JOIN absence_reasons ar ON ar.id = a.reason
        WHERE wd.employee_id = in_employee_id
            AND (ar.billable IS NULL OR ar.billable != 'unavailable')
        GROUP BY wd.employee_id, wd.work_day
    )
    SELECT COALESCE(SUM(hours), 0)
    FROM employee_daily_hours;
$$ LANGUAGE sql;



CREATE OR REPLACE FUNCTION public.accumulated_staffing_hours_new(from_date date, to_date date)
RETURNS TABLE (available_hours numeric, billable_hours numeric, nonbillable_hours numeric) AS
$$
    WITH staffing_hours AS (
        SELECT
            SUM(CASE WHEN p.billable = 'billable' THEN s.percentage * 7.5 / 100.0 ELSE 0 END) AS billable,
            SUM(CASE WHEN p.billable = 'nonbillable' THEN s.percentage * 7.5 / 100.0 ELSE 0 END) AS nonbillable
        FROM staffing s
        INNER JOIN projects p ON p.id = s.project
        WHERE s.date BETWEEN from_date AND to_date
            AND e.date_of_employment <= s.date
            AND (e.termination_date IS NULL OR e.termination_date >= s.date)
    )
    SELECT
        available_hours(from_date, to_date) AS available_hours,
        COALESCE(staffing_hours.billable, 0) AS billable_hours,
        COALESCE(staffing_hours.nonbillable, 0) AS nonbillable_hours
    FROM staffing_hours;
$$ LANGUAGE sql;
