-- Revert floq:drop_ledger_social_expense from pg

BEGIN;

ALTER TABLE ledger_tech_expense
    DROP CONSTRAINT ledger_tech_expense_expense_fkey,
    DROP CONSTRAINT ledger_tech_expense_is_tech,
    ALTER COLUMN type DROP DEFAULT;

ALTER TABLE ledger_fagutvikling_expense
    DROP CONSTRAINT ledger_fagutvikling_expense_expense_fkey,
    DROP CONSTRAINT ledger_fagutvikling_expense_is_fagutvikling,
    ALTER COLUMN type DROP DEFAULT;

-- Rebuilt rather than ADD VALUE: a label added in a transaction cannot be used in it, and
-- ledger_social_expense below defaults to it.
ALTER TYPE ledger_expense_type RENAME TO ledger_expense_type_old;

CREATE TYPE ledger_expense_type AS ENUM ('tech', 'fagutvikling', 'sosialt');

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

CREATE TABLE ledger_social_expense (
    expense_id        TEXT                CONSTRAINT ledger_social_expense_pkey PRIMARY KEY,
    type              ledger_expense_type NOT NULL DEFAULT 'sosialt'
                                          CONSTRAINT ledger_social_expense_is_sosialt CHECK (type = 'sosialt'),
    category          TEXT                NOT NULL,
    amount            NUMERIC(12, 2)      NOT NULL CONSTRAINT ledger_social_expense_amount_positive CHECK (amount > 0),
    participant_count INTEGER             NOT NULL
                                          CONSTRAINT ledger_social_expense_has_participants CHECK (participant_count > 0),

    CONSTRAINT ledger_social_expense_expense_fkey FOREIGN KEY (expense_id, type)
        REFERENCES ledger_expense (id, type) ON DELETE CASCADE
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_social_expense TO employee;

COMMIT;
