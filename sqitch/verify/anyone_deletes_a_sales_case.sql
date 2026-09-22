-- Verify floq:anyone_deletes_a_sales_case on pg

BEGIN;

DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE tablename = 'sales_case'
          AND policyname = 'sales_case_delete_policy'
          AND cmd = 'DELETE'
          AND qual = 'true'
    ) THEN
        RAISE EXCEPTION 'sales_case_delete_policy still restricts who may delete a case';
    END IF;
END;
$$;

ROLLBACK;
