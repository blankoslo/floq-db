-- Deploy floq:drop_ledger_social_expense to pg
-- requires: add_ledger_expenses

BEGIN;

-- A sosialt is an event now, in ledger_social_event, so nothing is ever this type again. Its
-- rows were deleted by hand; if one has turned up after all, stop rather than lose it.
DO
$$
BEGIN
    IF EXISTS (SELECT 1 FROM ledger_expense WHERE type = 'sosialt') THEN
        RAISE EXCEPTION 'ledger_expense still has sosialt rows';
    END IF;
END;
$$;

DROP TABLE ledger_social_expense;

-- Postgres cannot drop an enum label, so the type is rebuilt without it. What compares or
-- defaults to the type is dropped first and put back as it was.
ALTER TABLE ledger_tech_expense
    DROP CONSTRAINT ledger_tech_expense_expense_fkey,
    DROP CONSTRAINT ledger_tech_expense_is_tech,
    ALTER COLUMN type DROP DEFAULT;

ALTER TABLE ledger_fagutvikling_expense
    DROP CONSTRAINT ledger_fagutvikling_expense_expense_fkey,
    DROP CONSTRAINT ledger_fagutvikling_expense_is_fagutvikling,
    ALTER COLUMN type DROP DEFAULT;

ALTER TYPE ledger_expense_type RENAME TO ledger_expense_type_old;

CREATE TYPE ledger_expense_type AS ENUM ('tech', 'fagutvikling');

ALTER TABLE ledger_expense
    ALTER COLUMN type TYPE ledger_expense_type USING type::TEXT::ledger_expense_type;
ALTER TABLE ledger_tech_expense
    ALTER COLUMN type TYPE ledger_expense_type USING type::TEXT::ledger_expense_type;
ALTER TABLE ledger_fagutvikling_expense
    ALTER COLUMN type TYPE ledger_expense_type USING type::TEXT::ledger_expense_type;

DROP TYPE ledger_expense_type_old;

ALTER TABLE ledger_tech_expense
    ALTER COLUMN type SET DEFAULT 'tech',
    ADD CONSTRAINT ledger_tech_expense_is_tech CHECK (type = 'tech'),
    ADD CONSTRAINT ledger_tech_expense_expense_fkey FOREIGN KEY (expense_id, type)
        REFERENCES ledger_expense (id, type) ON DELETE CASCADE;

ALTER TABLE ledger_fagutvikling_expense
    ALTER COLUMN type SET DEFAULT 'fagutvikling',
    ADD CONSTRAINT ledger_fagutvikling_expense_is_fagutvikling CHECK (type = 'fagutvikling'),
    ADD CONSTRAINT ledger_fagutvikling_expense_expense_fkey FOREIGN KEY (expense_id, type)
        REFERENCES ledger_expense (id, type) ON DELETE CASCADE;

COMMIT;
