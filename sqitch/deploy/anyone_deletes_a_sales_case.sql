-- Deploy floq:anyone_deletes_a_sales_case to pg
-- requires: add_sales_pipeline

BEGIN;

-- Removing a card was an admin's, which meant whoever typed one wrong had to find
-- an admin to undo it. The board is the whole company's to add to, so it is the
-- whole company's to correct. Nothing is lost either way: the BEFORE DELETE
-- trigger keeps the entire row in sales_case_event, and it names who did it.
DROP POLICY sales_case_delete_policy ON sales_case;

CREATE POLICY sales_case_delete_policy ON sales_case FOR DELETE TO employee
    USING (true);

COMMIT;
