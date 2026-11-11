-- Revert floq:add_ledger_fagutvikling_amount from pg

BEGIN;

-- A basic fagutvikling has no hvor, rolle or ticket, travel and accommodation sums to put back,
-- so stop rather than lose it.
DO
$$
BEGIN
    IF EXISTS (SELECT 1 FROM ledger_fagutvikling_expense WHERE amount IS NOT NULL) THEN
        RAISE EXCEPTION 'ledger_fagutvikling_expense has basic fagutvikling rows';
    END IF;
END;
$$;

ALTER TABLE ledger_fagutvikling_expense
    DROP CONSTRAINT ledger_fagutvikling_expense_basic_or_costed,
    DROP COLUMN amount,
    ALTER COLUMN location SET NOT NULL,
    ALTER COLUMN role SET NOT NULL,
    ALTER COLUMN ticket SET NOT NULL,
    ALTER COLUMN travel SET NOT NULL,
    ALTER COLUMN accommodation SET NOT NULL;

COMMIT;
