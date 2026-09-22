-- Revert floq:add_sales_case_archived from pg

BEGIN;

DROP INDEX sales_case_board_idx;
CREATE INDEX sales_case_board_idx ON sales_case (stage_slug, stage_since DESC);

ALTER TABLE sales_case DROP COLUMN archived_at;

COMMIT;
