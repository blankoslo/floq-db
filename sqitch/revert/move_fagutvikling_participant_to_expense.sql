-- Revert floq:move_fagutvikling_participant_to_expense from pg

BEGIN;

CREATE TABLE ledger_fagutvikling_participant (
    expense_id    TEXT           NOT NULL REFERENCES ledger_fagutvikling_expense (expense_id) ON DELETE CASCADE,
    employee_id   INTEGER        NOT NULL REFERENCES employees (id),
    role          TEXT           NOT NULL,
    days          NUMERIC(5, 2)  NOT NULL CONSTRAINT ledger_fagutvikling_participant_days_positive CHECK (days > 0),
    ticket        NUMERIC(12, 2) NOT NULL CONSTRAINT ledger_fagutvikling_participant_ticket_not_negative CHECK (ticket >= 0),
    travel        NUMERIC(12, 2) NOT NULL CONSTRAINT ledger_fagutvikling_participant_travel_not_negative CHECK (travel >= 0),
    accommodation NUMERIC(12, 2) NOT NULL
                                 CONSTRAINT ledger_fagutvikling_participant_accommodation_not_negative CHECK (accommodation >= 0),

    CONSTRAINT ledger_fagutvikling_participant_pkey PRIMARY KEY (expense_id, employee_id)
);

-- Each expense's one person becomes its one participant.
INSERT INTO ledger_fagutvikling_participant (expense_id, employee_id, role, days, ticket, travel, accommodation)
SELECT expense_id, employee_id, role, days, ticket, travel, accommodation
FROM ledger_fagutvikling_expense;

-- Their constraints go with them.
ALTER TABLE ledger_fagutvikling_expense
    DROP COLUMN employee_id,
    DROP COLUMN role,
    DROP COLUMN days,
    DROP COLUMN ticket,
    DROP COLUMN travel,
    DROP COLUMN accommodation;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_fagutvikling_participant TO employee;

COMMIT;
