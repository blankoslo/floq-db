-- Revert floq:add_view_employee_project_responsible from pg

BEGIN;

-- XXX Add DDLs here.
DROP VIEW employee_project_responsible;

COMMIT;
