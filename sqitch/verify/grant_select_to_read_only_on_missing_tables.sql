-- Verify floq:grant_select_to_read_only_on_missing_tables on pg

BEGIN;

SET ROLE read_only;
SELECT * FROM employee_tenure_role WHERE false;
SELECT * FROM time_entry_comments WHERE false;
SELECT * FROM invoice_lock_events WHERE false;
SELECT * FROM project_members WHERE false;
SELECT * FROM project_code_pins WHERE false;
SELECT * FROM week_balance_confirmations WHERE false;
SELECT * FROM employee_project_responsible WHERE false;
RESET ROLE;

ROLLBACK;
