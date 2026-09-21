-- Revert floq:add_sales_case_attachments from pg

BEGIN;

DROP TABLE sales_case_attachment;

DROP FUNCTION log_sales_attachment_change();
DROP FUNCTION set_sales_attachment_uploader();

DELETE FROM sales_event_kind WHERE slug IN ('attachment_added', 'attachment_removed');

COMMIT;
