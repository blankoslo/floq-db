-- Revert floq:add_parkert_sales_stage from pg

BEGIN;

DELETE FROM sales_stage WHERE slug = 'parkert';

COMMIT;
