-- Deploy floq:add_invoice_lock_events_table to pg
-- requires: time_tracking_tables
-- requires: employees_table

BEGIN;

CREATE TABLE invoice_lock_events (
    id          TEXT CONSTRAINT invoice_lock_events_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id  TEXT NOT NULL REFERENCES projects(id),
    creator_id  INTEGER NOT NULL REFERENCES employees(id),
    created_at  TIMESTAMP NOT NULL DEFAULT now(),
    order_id    INTEGER NOT NULL,
    commit_date DATE NOT NULL
);

COMMIT;
