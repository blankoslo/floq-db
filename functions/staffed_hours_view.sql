CREATE OR REPLACE VIEW staffed_hours AS
(WITH staffing_totals AS (
	SELECT
		employee,
		date,
		COALESCE(SUM(percentage), 0) AS staffing_percentage
	FROM
		staffing
	WHERE NOT is_holiday(date)
	GROUP BY
		employee,
		date
),
absence_totals AS (
	SELECT
		employee_id AS employee,
		date,
		COALESCE(SUM(percentage), 0) AS absence_percentage
	FROM
		absence
	GROUP BY
		employee_id,
		date
)
SELECT
	COALESCE(s.employee, a.employee) AS employee,
	COALESCE(s.date, a.date) AS date,
	COALESCE((s.staffing_percentage * 0.375) - (GREATEST(s.staffing_percentage + a.absence_percentage - 100, 0)) * 0.375, 0) AS total_staffed_hours
FROM
	staffing_totals s
	FULL OUTER JOIN absence_totals a ON s.employee = a.employee
	AND s.date = a.date);
