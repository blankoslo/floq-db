-- Revert floq:grant_select_on_employee_responsible_view_trak_read_only from pg

BEGIN;

REVOKE SELECT ON employee_project_responsible TO trak_read_only;

COMMIT;
