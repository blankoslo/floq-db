-- Deploy floq:grant_select_to_read_only_on_missing_tables to pg

BEGIN;

-- Backfill SELECT for read_only on tables/views added since the one-time
-- "GRANT SELECT ON ALL TABLES IN SCHEMA public" in add_read_only_user, which
-- only covered tables that existed at that point in time. Going forward,
-- read_only should be granted explicitly per table/view, the same way employee is.
--
-- Trak tables (from add_trak) are intentionally excluded from read_only access.

GRANT SELECT ON TABLE employee_tenure_role TO read_only;
GRANT SELECT ON TABLE time_entry_comments TO read_only;
GRANT SELECT ON TABLE invoice_lock_events TO read_only;
GRANT SELECT ON TABLE project_members TO read_only;
GRANT SELECT ON TABLE project_code_pins TO read_only;
GRANT SELECT ON TABLE week_balance_confirmations TO read_only;
GRANT SELECT ON employee_project_responsible TO read_only;

COMMIT;
