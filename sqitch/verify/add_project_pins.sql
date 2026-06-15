-- Verify floq:add_project_pins on pg

BEGIN;

SELECT id, employee_id, project_id, pin_type, week, created FROM project_code_pins;

ROLLBACK;
