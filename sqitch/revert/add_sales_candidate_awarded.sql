BEGIN;

DROP POLICY sales_candidate_update_policy ON sales_candidate;
REVOKE UPDATE (awarded) ON TABLE sales_candidate FROM employee;

DROP TRIGGER sales_candidate_award_change ON sales_candidate;
DROP TRIGGER sales_candidate_awarded_at ON sales_candidate;
DROP FUNCTION log_sales_candidate_award_change();
DROP FUNCTION set_sales_candidate_awarded_at();

ALTER TABLE sales_candidate
    DROP COLUMN awarded_at,
    DROP COLUMN awarded;

DELETE FROM sales_case_event WHERE kind_slug IN ('candidate_awarded', 'candidate_unawarded');
DELETE FROM person_card_event WHERE kind_slug IN ('candidate_awarded', 'candidate_unawarded');
DELETE FROM sales_event_kind WHERE slug IN ('candidate_awarded', 'candidate_unawarded');

COMMIT;
