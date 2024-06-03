-- Verify floq:grant_select_on_employee_responsible_view_trak_read_only on pg

BEGIN;

SET ROLE trak_read_only;
SELECT * FROM employee_project_responsible;
RESET ROLE;

ROLLBACK;
