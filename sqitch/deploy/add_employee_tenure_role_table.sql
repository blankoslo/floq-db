-- Deploy floq:add_employee_tenure_role_table to pg
-- requires: employees_table
-- requires: enable_employee_row_level_security

BEGIN;

CREATE TABLE employee_tenure_role (
    id          TEXT CONSTRAINT employee_tenure_role_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
    from_date   DATE NOT NULL,
    to_date     DATE,
    employee_id INTEGER REFERENCES employees(id) NOT NULL,
    tenure_role TEXT NOT NULL,
    created     TIMESTAMP DEFAULT now()
);

GRANT SELECT ON TABLE employee_tenure_role TO employee;

SELECT enable_default_row_level_security('employee_tenure_role', 'check_admin_write_access()');

COMMIT;
