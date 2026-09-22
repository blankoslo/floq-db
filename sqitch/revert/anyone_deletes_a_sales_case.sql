-- Revert floq:anyone_deletes_a_sales_case from pg

BEGIN;

DROP POLICY sales_case_delete_policy ON sales_case;

CREATE POLICY sales_case_delete_policy ON sales_case FOR DELETE TO employee
    USING (check_admin_write_access());

COMMIT;
