-- Verify floq:add_view_employee_project_responsible on pg

BEGIN;

SELECT * FROM employee_project_responsible WHERE false;

ROLLBACK;
