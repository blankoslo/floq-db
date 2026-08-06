-- Deploy floq:add_week_balance_confirmations_table to pg
-- requires: employees_table

BEGIN;

CREATE TABLE week_balance_confirmations (
    id         BIGSERIAL PRIMARY KEY,
    employee   INTEGER NOT NULL REFERENCES employees(id),
    creator    INTEGER NOT NULL REFERENCES employees(id),
    week_start DATE NOT NULL,
    minutes    INTEGER NOT NULL,
    confirmed  BOOLEAN NOT NULL DEFAULT true,
    created    TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- week_start must be the ISO Monday of the week it describes.
    CONSTRAINT week_balance_confirmations_week_start_is_monday
        CHECK (EXTRACT(ISODOW FROM week_start) = 1)
);

CREATE INDEX week_balance_confirmations_lookup_idx
    ON week_balance_confirmations (employee, week_start, created DESC);

GRANT SELECT, INSERT ON TABLE week_balance_confirmations TO employee;
GRANT USAGE, SELECT ON SEQUENCE week_balance_confirmations_id_seq TO employee;

COMMIT;
