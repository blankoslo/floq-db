-- Revert floq:add_sales_case_attachments from pg

BEGIN;

DROP TABLE sales_case_attachment;

DROP FUNCTION log_sales_attachment_change();
DROP FUNCTION set_sales_attachment_uploader();

-- Real attachment_added/attachment_removed rows already exist on sales_case_event.
-- NOT VALID on the re-add so that history is not re-checked, while new writes
-- still are.
ALTER TABLE sales_case_event DROP CONSTRAINT sales_case_event_kind_slug_fkey;

DELETE FROM sales_event_kind WHERE slug IN ('attachment_added', 'attachment_removed');

ALTER TABLE sales_case_event
    ADD CONSTRAINT sales_case_event_kind_slug_fkey FOREIGN KEY (kind_slug) REFERENCES sales_event_kind (slug) NOT VALID;

COMMIT;
