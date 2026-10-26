-- Revert floq:drop_staffing from pg

BEGIN;

-- The table and views come back empty: a pg_dump of staffing taken before the
-- deploy is what restores the rows. The functions come back by running
-- functions/deploy.sh from a commit before this change.
CREATE TABLE staffing (
    employee   INTEGER NOT NULL,
    project    TEXT    NOT NULL,
    date       DATE    NOT NULL,
    percentage INTEGER NOT NULL DEFAULT 100,
    CONSTRAINT staffing_pkey PRIMARY KEY (employee, project, date),
    CONSTRAINT staffing_employee_fkey FOREIGN KEY (employee) REFERENCES employees(id) ON UPDATE CASCADE,
    CONSTRAINT staffing_project_fkey FOREIGN KEY (project) REFERENCES projects(id) ON UPDATE CASCADE
);

GRANT ALL ON TABLE staffing TO employee;
GRANT SELECT ON TABLE staffing TO read_only, trak_read_only;

CREATE VIEW staffed_hours AS
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

CREATE VIEW employee_project_responsible AS
SELECT most_staffed.employee as employee,
       projects.responsible as project_responsible
FROM (SELECT employee,
             project
      FROM (SELECT employee,
                   project,
                   total,
                   row_number() OVER (PARTITION BY employee ORDER BY total DESC) as rank
            FROM (SELECT employee,
                         project,
                         count(employee) AS total
                  FROM staffing
                  WHERE date > (now() - '22 days'::interval)
                    AND date < (now() + '21 days'::interval)
                    AND project != 'FER1000'
                    AND EXISTS (SELECT id
                      FROM projects
                      WHERE projects.id = staffing.project
                    AND active = true)
                  GROUP BY employee, project) AS staffed_project) ranked
      WHERE ranked.rank = 1) AS most_staffed
         JOIN projects ON most_staffed.project = projects.id;

GRANT SELECT ON employee_project_responsible TO employee, read_only, trak_read_only;

COMMIT;
