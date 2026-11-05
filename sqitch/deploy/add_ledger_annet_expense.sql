-- Deploy floq:add_ledger_annet_expense to pg
-- requires: drop_ledger_social_expense

BEGIN;

-- Rebuilt rather than ADD VALUE: a label added in a transaction cannot be used in it, and
-- ledger_annet_expense below defaults to it. What compares or defaults to the type is dropped
-- first and put back as it was.
ALTER TABLE ledger_tech_expense
    DROP CONSTRAINT ledger_tech_expense_expense_fkey,
    DROP CONSTRAINT ledger_tech_expense_is_tech,
    ALTER COLUMN type DROP DEFAULT;

ALTER TABLE ledger_fagutvikling_expense
    DROP CONSTRAINT ledger_fagutvikling_expense_expense_fkey,
    DROP CONSTRAINT ledger_fagutvikling_expense_is_fagutvikling,
    ALTER COLUMN type DROP DEFAULT;

ALTER TYPE ledger_expense_type RENAME TO ledger_expense_type_old;

CREATE TYPE ledger_expense_type AS ENUM ('tech', 'fagutvikling', 'annet');

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

CREATE TABLE ledger_annet_expense (
    expense_id    TEXT                CONSTRAINT ledger_annet_expense_pkey PRIMARY KEY,
    type          ledger_expense_type NOT NULL DEFAULT 'annet'
                                      CONSTRAINT ledger_annet_expense_is_annet CHECK (type = 'annet'),
    amount        NUMERIC(12, 2)      NOT NULL CONSTRAINT ledger_annet_expense_amount_positive CHECK (amount > 0),
    -- Tripletex's cost category the utlegg was booked under, by name. Null when Blank paid, since
    -- nothing went to Tripletex.
    cost_category TEXT,

    CONSTRAINT ledger_annet_expense_expense_fkey FOREIGN KEY (expense_id, type)
        REFERENCES ledger_expense (id, type) ON DELETE CASCADE
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_annet_expense TO employee;

COMMIT;
