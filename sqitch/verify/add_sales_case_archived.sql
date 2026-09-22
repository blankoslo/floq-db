-- Verify floq:add_sales_case_archived on pg

BEGIN;

SELECT archived_at FROM sales_case WHERE FALSE;

DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = 'sales_case_board_idx'
          AND i.indpred IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'the board index no longer leaves the archived cards out';
    END IF;
END;
$$;

ROLLBACK;
