BEGIN;

DROP TABLE sales_candidate;

DROP FUNCTION log_sales_candidate_change();
DROP FUNCTION set_sales_candidate_author();

DELETE FROM sales_case_event WHERE kind_slug IN ('candidate_added', 'candidate_removed');
DELETE FROM person_card_event WHERE kind_slug IN ('candidate_added', 'candidate_removed');
DELETE FROM sales_event_kind WHERE slug IN ('candidate_added', 'candidate_removed');

COMMIT;
