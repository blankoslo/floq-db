-- Deploy floq:add_ledger_fagutvikling_amount to pg
-- requires: move_fagutvikling_participant_to_expense

BEGIN;

-- A basic fagutvikling, such as a book or a course, has no hvor or rolle, and one receipt: its
-- utlegg is the expense's own tripletex_expense_id, as tech's is, and its sum is amount. The older
-- rows keep hvor, rolle and the ticket, travel and accommodation sums, and have no amount.
ALTER TABLE ledger_fagutvikling_expense
    ALTER COLUMN location DROP NOT NULL,
    ALTER COLUMN role DROP NOT NULL,
    ALTER COLUMN ticket DROP NOT NULL,
    ALTER COLUMN travel DROP NOT NULL,
    ALTER COLUMN accommodation DROP NOT NULL,
    ADD COLUMN amount NUMERIC(12, 2) CONSTRAINT ledger_fagutvikling_expense_amount_positive CHECK (amount > 0),
    ADD CONSTRAINT ledger_fagutvikling_expense_basic_or_costed CHECK (
        (amount IS NOT NULL AND num_nulls(location, role, ticket, travel, accommodation) = 5)
        OR (amount IS NULL AND num_nonnulls(location, role, ticket, travel, accommodation) = 5)
    );

COMMIT;
