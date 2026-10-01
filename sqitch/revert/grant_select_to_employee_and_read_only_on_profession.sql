-- Revert floq:grant_select_to_employee_and_read_only_on_profession from pg

BEGIN;

REVOKE SELECT ON TABLE profession FROM employee;
REVOKE SELECT ON TABLE profession FROM read_only;

COMMIT;
