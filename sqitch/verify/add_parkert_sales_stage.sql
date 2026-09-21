-- Verify floq:add_parkert_sales_stage on pg

BEGIN;

DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM sales_stage
        WHERE slug = 'parkert'
          AND sort_order = 45
          AND NOT is_terminal
          AND hides_after_months = 6
    ) THEN
        RAISE EXCEPTION 'the parkert stage is missing or does not match the expected contract';
    END IF;
END;
$$;

ROLLBACK;
