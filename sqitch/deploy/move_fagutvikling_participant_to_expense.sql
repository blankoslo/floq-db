-- Deploy floq:move_fagutvikling_participant_to_expense to pg
-- requires: add_ledger_expenses

BEGIN;

-- A fagutvikling expense now covers one person, so the participant's fields move onto
-- the expense itself. Both tables are empty, so nothing is copied; if an expense has
-- turned up after all, adding the NOT NULL columns fails rather than lose its participant.
ALTER TABLE ledger_fagutvikling_expense
    ADD COLUMN employee_id   INTEGER        NOT NULL REFERENCES employees (id),
    ADD COLUMN role          TEXT           NOT NULL,
    ADD COLUMN days          NUMERIC(5, 2)  NOT NULL CONSTRAINT ledger_fagutvikling_expense_days_positive CHECK (days > 0),
    ADD COLUMN ticket        NUMERIC(12, 2) NOT NULL CONSTRAINT ledger_fagutvikling_expense_ticket_not_negative CHECK (ticket >= 0),
    ADD COLUMN travel        NUMERIC(12, 2) NOT NULL CONSTRAINT ledger_fagutvikling_expense_travel_not_negative CHECK (travel >= 0),
    ADD COLUMN accommodation NUMERIC(12, 2) NOT NULL
                             CONSTRAINT ledger_fagutvikling_expense_accommodation_not_negative CHECK (accommodation >= 0);

DROP TABLE ledger_fagutvikling_participant;

COMMIT;
