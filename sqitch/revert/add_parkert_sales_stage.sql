-- Revert floq:add_parkert_sales_stage from pg

BEGIN;

-- Real cases parked and later moved on left sales_case_event rows naming this
-- stage, and cases still parked today sit in it right now. NOT VALID on the
-- re-adds so neither is re-checked, while new writes still are: this revert is
-- undoing a stage that real board cards currently occupy, not just history.
ALTER TABLE sales_case_event
    DROP CONSTRAINT sales_case_event_from_stage_fkey,
    DROP CONSTRAINT sales_case_event_to_stage_fkey;

ALTER TABLE sales_case
    DROP CONSTRAINT sales_case_stage_slug_fkey;

DELETE FROM sales_stage WHERE slug = 'parkert';

ALTER TABLE sales_case_event
    ADD CONSTRAINT sales_case_event_from_stage_fkey FOREIGN KEY (from_stage) REFERENCES sales_stage (slug) NOT VALID,
    ADD CONSTRAINT sales_case_event_to_stage_fkey FOREIGN KEY (to_stage) REFERENCES sales_stage (slug) NOT VALID;

ALTER TABLE sales_case
    ADD CONSTRAINT sales_case_stage_slug_fkey FOREIGN KEY (stage_slug) REFERENCES sales_stage (slug) NOT VALID;

COMMIT;
