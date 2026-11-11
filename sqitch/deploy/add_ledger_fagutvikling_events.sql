-- Deploy floq:add_ledger_fagutvikling_events to pg
-- requires: employees_table
-- requires: add_employee_user

BEGIN;

-- For uuid_generate_v4(). Earlier changes already create it, so revert leaves it be.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- The receipt section an expense was added under: billett, reise or kost og losji.
CREATE TYPE ledger_fagutvikling_cost AS ENUM ('ticket', 'travel', 'accommodation');

-- A fag arrangement, such as a conference. Anyone may join it while it is open, and its creator
-- closes it by sending it to Slack.
CREATE TABLE ledger_fagutvikling_event (
    id         TEXT        CONSTRAINT ledger_fagutvikling_event_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    title      TEXT        NOT NULL,
    date       DATE        NOT NULL,
    location   TEXT        NOT NULL
                           CONSTRAINT ledger_fagutvikling_event_location_norge_or_utland
                           CHECK (location IN ('Norge', 'Utland')),
    comment    TEXT,
    created_by INTEGER     NOT NULL CONSTRAINT ledger_fagutvikling_event_created_by_fkey REFERENCES employees (id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- When it went to Slack. Null while open.
    closed_at  TIMESTAMPTZ,
    -- Its first post, which closing it again after a reopen replies under.
    slack_ts   TEXT
);

-- Everyone who joined, whether or not they paid for anything.
CREATE TABLE ledger_fagutvikling_event_attendee (
    event_id    TEXT          NOT NULL
                              CONSTRAINT ledger_fagutvikling_event_attendee_event_id_fkey
                              REFERENCES ledger_fagutvikling_event (id) ON DELETE CASCADE,
    employee_id INTEGER       NOT NULL
                              CONSTRAINT ledger_fagutvikling_event_attendee_employee_id_fkey REFERENCES employees (id),
    role        TEXT          NOT NULL,
    days        NUMERIC(5, 2) NOT NULL CONSTRAINT ledger_fagutvikling_event_attendee_days_positive CHECK (days > 0),
    sharing     TEXT          NOT NULL,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT ledger_fagutvikling_event_attendee_pkey PRIMARY KEY (event_id, employee_id)
);

CREATE TABLE ledger_fagutvikling_event_expense (
    id                   TEXT                     CONSTRAINT ledger_fagutvikling_event_expense_pkey PRIMARY KEY
                                                  DEFAULT uuid_generate_v4(),
    event_id             TEXT                     NOT NULL
                                                  CONSTRAINT ledger_fagutvikling_event_expense_event_id_fkey
                                                  REFERENCES ledger_fagutvikling_event (id) ON DELETE CASCADE,
    -- Reimbursed: every expense here is a receipt and its own utlegg, never an invoice Blank paid.
    added_by             INTEGER                  NOT NULL
                                                  CONSTRAINT ledger_fagutvikling_event_expense_added_by_fkey
                                                  REFERENCES employees (id),
    -- Unique here only: the other ledger tables have their own.
    tripletex_expense_id BIGINT                   NOT NULL
                                                  CONSTRAINT ledger_fagutvikling_event_expense_tripletex_expense_id_key UNIQUE,
    title                TEXT                     NOT NULL,
    amount               NUMERIC(12, 2)           NOT NULL
                                                  CONSTRAINT ledger_fagutvikling_event_expense_amount_positive CHECK (amount > 0),
    cost                 ledger_fagutvikling_cost NOT NULL,
    created_at           TIMESTAMPTZ              NOT NULL DEFAULT now()
);

-- Who an expense is split between, equally. The platform keeps them to the event's attendees.
CREATE TABLE ledger_fagutvikling_event_expense_share (
    expense_id  TEXT    NOT NULL
                        CONSTRAINT ledger_fagutvikling_event_expense_share_expense_id_fkey
                        REFERENCES ledger_fagutvikling_event_expense (id) ON DELETE CASCADE,
    employee_id INTEGER NOT NULL
                        CONSTRAINT ledger_fagutvikling_event_expense_share_employee_id_fkey REFERENCES employees (id),

    CONSTRAINT ledger_fagutvikling_event_expense_share_pkey PRIMARY KEY (expense_id, employee_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
    ledger_fagutvikling_event, ledger_fagutvikling_event_attendee,
    ledger_fagutvikling_event_expense, ledger_fagutvikling_event_expense_share
TO employee;

COMMIT;
