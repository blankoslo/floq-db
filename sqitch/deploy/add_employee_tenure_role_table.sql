-- Deploy floq:add_employee_tenure_role_table to pg

BEGIN;

CREATE TABLE employee_tenure_role (
    id          TEXT CONSTRAINT employee_tenure_role_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    year        INTEGER NOT NULL,
    employee_id INTEGER REFERENCES employees(id) NOT NULL,
    tenure_role TEXT NOT NULL,
    created     DATE DEFAULT now()
);

COMMIT;
