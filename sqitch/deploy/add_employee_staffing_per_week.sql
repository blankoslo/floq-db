BEGIN;

CREATE VIEW employee_staffing_per_week AS
SELECT staffing.employee AS employee_id,
        employees.first_name,
        employees.last_name,
        employees.date_of_employment,
        employees.termination_date,
        date_part('year'::text, staffing.date) AS year,
        date_part('week'::text, staffing.date) AS week,
        array_agg(date_part('day'::text, staffing.date)) AS days,
        staffing.project AS project_id,
        count(staffing.employee) AS n_days
FROM staffing
JOIN employees ON staffing.employee = employees.id
GROUP BY staffing.employee, employees.first_name, employees.last_name, employees.date_of_employment, employees.termination_date, (date_part('year'::text, staffing.date)), (date_part('week'::text, staffing.date)), staffing.project
ORDER BY employees.first_name, (date_part('year'::text, staffing.date)), (date_part('week'::text, staffing.date));

GRANT SELECT ON employee_project_responsible TO employee;

COMMIT;