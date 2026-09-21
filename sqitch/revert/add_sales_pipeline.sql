-- Revert floq:add_sales_pipeline from pg

BEGIN;

DROP TABLE sales_case_event;
DROP TABLE sales_case;
DROP TABLE sales_event_kind;
DROP TABLE sales_stage;

DROP FUNCTION set_sales_case_event_author();
DROP FUNCTION log_sales_case_deleted();
DROP FUNCTION log_sales_case_field_change();
DROP FUNCTION log_sales_case_stage_change();
DROP FUNCTION log_sales_case_created();
DROP FUNCTION set_sales_case_stage_since();
DROP FUNCTION set_sales_case_author();
DROP FUNCTION logged_in_employee_id();

COMMIT;
