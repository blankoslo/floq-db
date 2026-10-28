-- Deploy floq:add_ledger_expenses to pg
-- requires: employees_table

BEGIN;

-- For uuid_generate_v4(). Earlier changes already create it, so revert leaves it be.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Utlegg from the ledger app. `expense` and `expense_type` are already taken by the
-- project balance, hence the prefix. Keys match the app's: tech, fagutvikling, sosialt.
CREATE TYPE ledger_expense_type AS ENUM ('tech', 'fagutvikling', 'sosialt');

-- What every type has. Each type's own fields live in a table of its own, joined 1:1.
CREATE TABLE ledger_expense (
    id                   TEXT                CONSTRAINT ledger_expense_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    type                 ledger_expense_type NOT NULL,
    date                 DATE                NOT NULL,
    description          TEXT                NOT NULL,
    -- Who is reimbursed: "Hvem kjøpte det?" on tech, "Hvem betalte?" on the others.
    paid_by              INTEGER             NOT NULL REFERENCES employees (id),
    comment              TEXT,
    charge_to_project    BOOLEAN             NOT NULL DEFAULT FALSE,
    tripletex_expense_id BIGINT              CONSTRAINT ledger_expense_tripletex_expense_id_key UNIQUE,
    created_by           INTEGER             REFERENCES employees (id),
    created_at           TIMESTAMPTZ         NOT NULL DEFAULT now(),

    -- The target of each type table's foreign key, so a row can only hang off an
    -- expense of its own type.
    CONSTRAINT ledger_expense_id_type_key UNIQUE (id, type)
);

CREATE TABLE ledger_tech_expense (
    expense_id    TEXT                CONSTRAINT ledger_tech_expense_pkey PRIMARY KEY,
    type          ledger_expense_type NOT NULL DEFAULT 'tech'
                                      CONSTRAINT ledger_tech_expense_is_tech CHECK (type = 'tech'),
    category      TEXT                NOT NULL,
    amount        NUMERIC(12, 2)      NOT NULL CONSTRAINT ledger_tech_expense_amount_positive CHECK (amount > 0),
    -- Null when it was bought for Blank rather than for one person.
    purchased_for INTEGER             REFERENCES employees (id),

    CONSTRAINT ledger_tech_expense_expense_fkey FOREIGN KEY (expense_id, type)
        REFERENCES ledger_expense (id, type) ON DELETE CASCADE
);

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

CREATE TABLE ledger_fagutvikling_expense (
    expense_id TEXT                CONSTRAINT ledger_fagutvikling_expense_pkey PRIMARY KEY,
    type       ledger_expense_type NOT NULL DEFAULT 'fagutvikling'
                                   CONSTRAINT ledger_fagutvikling_expense_is_fagutvikling CHECK (type = 'fagutvikling'),
    location   TEXT                NOT NULL,
    sharing    TEXT                NOT NULL,

    CONSTRAINT ledger_fagutvikling_expense_expense_fkey FOREIGN KEY (expense_id, type)
        REFERENCES ledger_expense (id, type) ON DELETE CASCADE
);

-- One expense may cover several people. Each one's costs count toward their own
-- totals, while paid_by on the expense is reimbursed for all of them.
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

COMMIT;
