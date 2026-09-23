BEGIN;

DROP TABLE sales_case_project;

DROP FUNCTION log_sales_case_project_change();
DROP FUNCTION set_sales_case_project_author();

DELETE FROM sales_case_event WHERE kind_slug IN ('project_added', 'project_removed');
DELETE FROM sales_event_kind WHERE slug IN ('project_added', 'project_removed');

COMMIT;
