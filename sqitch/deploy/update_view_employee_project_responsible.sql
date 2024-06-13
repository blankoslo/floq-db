-- Deploy floq:update_view_employee_project_responsible to pg

BEGIN;

CREATE OR REPLACE VIEW employee_project_responsible AS
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

COMMIT;
