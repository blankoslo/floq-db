BEGIN;

CREATE FUNCTION has_salg_access()
    RETURNS BOOLEAN
    LANGUAGE sql
    STABLE
AS
$$
SELECT EXISTS (
    SELECT 1
    FROM employee_role
    WHERE employee_id = logged_in_employee_id()
      AND role_type = 'salg'
);
$$;

GRANT EXECUTE ON FUNCTION has_salg_access() TO employee;

ALTER FUNCTION log_sales_candidate_change() SECURITY DEFINER SET search_path = public;

INSERT INTO employee_role (employee_id, role_type)
SELECT e.id, 'salg'
FROM employees e
WHERE lower(e.first_name || ' ' || e.last_name) IN ('knut magnus backer', 'jahn arne johnsen')
  AND NOT EXISTS (SELECT 1 FROM employee_role r WHERE r.employee_id = e.id AND r.role_type = 'salg');

DROP POLICY person_track_select_policy ON person_track;
CREATE POLICY person_track_select_policy ON person_track FOR SELECT USING (has_salg_access());

DROP POLICY person_card_select_policy ON person_card;
DROP POLICY person_card_insert_policy ON person_card;
DROP POLICY person_card_update_policy ON person_card;
DROP POLICY person_card_delete_policy ON person_card;
CREATE POLICY person_card_select_policy ON person_card FOR SELECT USING (has_salg_access());
CREATE POLICY person_card_insert_policy ON person_card FOR INSERT TO employee
    WITH CHECK (has_salg_access());
CREATE POLICY person_card_update_policy ON person_card FOR UPDATE TO employee
    USING (has_salg_access()) WITH CHECK (has_salg_access());
CREATE POLICY person_card_delete_policy ON person_card FOR DELETE TO employee
    USING (has_salg_access() AND employee_id IS NULL);

DROP POLICY person_card_event_select_policy ON person_card_event;
CREATE POLICY person_card_event_select_policy ON person_card_event FOR SELECT USING (has_salg_access());

DROP POLICY sales_candidate_select_policy ON sales_candidate;
DROP POLICY sales_candidate_insert_policy ON sales_candidate;
DROP POLICY sales_candidate_update_policy ON sales_candidate;
DROP POLICY sales_candidate_delete_policy ON sales_candidate;
CREATE POLICY sales_candidate_select_policy ON sales_candidate FOR SELECT USING (has_salg_access());
CREATE POLICY sales_candidate_insert_policy ON sales_candidate FOR INSERT TO employee
    WITH CHECK (has_salg_access());
CREATE POLICY sales_candidate_update_policy ON sales_candidate FOR UPDATE TO employee
    USING (has_salg_access()) WITH CHECK (has_salg_access());
CREATE POLICY sales_candidate_delete_policy ON sales_candidate FOR DELETE TO employee
    USING (has_salg_access());

DROP POLICY sales_case_event_select_policy ON sales_case_event;
CREATE POLICY sales_case_event_select_policy ON sales_case_event FOR SELECT
    USING (kind_slug NOT IN ('candidate_added', 'candidate_removed', 'candidate_awarded', 'candidate_unawarded')
           OR has_salg_access());

COMMIT;
