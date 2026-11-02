-- Deploy floq:add_ledger_social_events to pg
-- requires: employees_table
-- requires: add_employee_user

BEGIN;

-- For uuid_generate_v4(). Earlier changes already create it, so revert leaves it be.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- A sosialt arrangement in the ledger app. Anyone may add an utgift to it while it is open, and
-- its creator closes it by sending it to Slack.
CREATE TABLE ledger_social_event (
    id                TEXT        CONSTRAINT ledger_social_event_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    title             TEXT        NOT NULL,
    date              DATE        NOT NULL,
    -- One of the app's activity categories, which it keeps itself, as it does tech's.
    category          TEXT        NOT NULL,
    -- A headcount: most who attend never add an utgift.
    participant_count INTEGER     NOT NULL
                                  CONSTRAINT ledger_social_event_has_participants CHECK (participant_count > 0),
    comment           TEXT,
    created_by        INTEGER     NOT NULL REFERENCES employees (id),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- When it went to Slack. Null while open; after it, nothing on the event changes.
    closed_at         TIMESTAMPTZ
);

CREATE TABLE ledger_social_event_utgift (
    id                   TEXT           CONSTRAINT ledger_social_event_utgift_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id             TEXT           NOT NULL REFERENCES ledger_social_event (id) ON DELETE CASCADE,
    -- Reimbursed when it is an utlegg; whoever typed it in when it is an invoice.
    added_by             INTEGER        NOT NULL REFERENCES employees (id),
    -- Null for an invoice Blank paid. Unique here only: ledger_expense has its own.
    tripletex_expense_id BIGINT         CONSTRAINT ledger_social_event_utgift_tripletex_expense_id_key UNIQUE,
    title                TEXT           NOT NULL,
    amount               NUMERIC(12, 2) NOT NULL
                                        CONSTRAINT ledger_social_event_utgift_amount_positive CHECK (amount > 0),
    created_at           TIMESTAMPTZ    NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ledger_social_event, ledger_social_event_utgift TO employee;

COMMIT;
