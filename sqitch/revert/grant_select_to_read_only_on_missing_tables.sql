-- Revert floq:grant_select_to_read_only_on_missing_tables from pg

BEGIN;

REVOKE SELECT ON TABLE employee_tenure_role FROM read_only;
REVOKE SELECT ON TABLE time_entry_comments FROM read_only;
REVOKE SELECT ON TABLE invoice_lock_events FROM read_only;
REVOKE SELECT ON TABLE project_members FROM read_only;
REVOKE SELECT ON TABLE project_code_pins FROM read_only;
REVOKE SELECT ON TABLE week_balance_confirmations FROM read_only;
REVOKE SELECT ON employee_project_responsible FROM read_only;

COMMIT;
