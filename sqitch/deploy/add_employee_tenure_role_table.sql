-- Deploy floq:add_employee_tenure_role_table to pg
-- requires: employees_table

BEGIN;

CREATE TABLE employee_tenure_role (
    id          TEXT CONSTRAINT employee_tenure_role_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    from_date   DATE NOT NULL,
    to_date     DATE,
    employee_id INTEGER REFERENCES employees(id) NOT NULL,
    tenure_role TEXT NOT NULL,
    created     TIMESTAMP DEFAULT now()
);

GRANT ALL PRIVILEGES ON employee_tenure_role TO employee;

COMMIT;
