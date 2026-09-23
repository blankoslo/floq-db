BEGIN;

DROP POLICY sales_case_event_select_policy ON sales_case_event;
CREATE POLICY sales_case_event_select_policy ON sales_case_event FOR SELECT USING (true);

DROP POLICY sales_candidate_select_policy ON sales_candidate;
DROP POLICY sales_candidate_insert_policy ON sales_candidate;
DROP POLICY sales_candidate_update_policy ON sales_candidate;
DROP POLICY sales_candidate_delete_policy ON sales_candidate;
CREATE POLICY sales_candidate_select_policy ON sales_candidate FOR SELECT USING (true);
CREATE POLICY sales_candidate_insert_policy ON sales_candidate FOR INSERT TO employee WITH CHECK (true);
CREATE POLICY sales_candidate_update_policy ON sales_candidate FOR UPDATE TO employee
    USING (true) WITH CHECK (true);
CREATE POLICY sales_candidate_delete_policy ON sales_candidate FOR DELETE TO employee USING (true);

DROP POLICY person_card_event_select_policy ON person_card_event;
CREATE POLICY person_card_event_select_policy ON person_card_event FOR SELECT USING (true);

DROP POLICY person_card_select_policy ON person_card;
DROP POLICY person_card_insert_policy ON person_card;
DROP POLICY person_card_update_policy ON person_card;
DROP POLICY person_card_delete_policy ON person_card;
CREATE POLICY person_card_select_policy ON person_card FOR SELECT USING (true);
CREATE POLICY person_card_insert_policy ON person_card FOR INSERT TO employee WITH CHECK (true);
CREATE POLICY person_card_update_policy ON person_card FOR UPDATE TO employee
    USING (true) WITH CHECK (true);
CREATE POLICY person_card_delete_policy ON person_card FOR DELETE TO employee
    USING (employee_id IS NULL);

DROP POLICY person_track_select_policy ON person_track;
CREATE POLICY person_track_select_policy ON person_track FOR SELECT USING (true);

DELETE FROM employee_role WHERE role_type = 'salg';

ALTER FUNCTION log_sales_candidate_change() SECURITY INVOKER RESET search_path;

DROP FUNCTION has_salg_access();

COMMIT;
