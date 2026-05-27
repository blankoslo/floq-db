-- Deploy floq:create_project_members_table to pg
-- requires: employees_table
-- requires: time_tracking_tables

BEGIN;

CREATE TABLE project_members (
  id          SERIAL PRIMARY KEY,
  employee_id integer NOT NULL REFERENCES employees(id),
  customer_id integer NOT NULL REFERENCES customers(id),
  hourly_rate numeric NOT NULL,
  from_date   date    NOT NULL
);

GRANT ALL PRIVILEGES ON TABLE project_members TO employee;
GRANT ALL PRIVILEGES ON SEQUENCE project_members_id_seq TO employee;

COMMIT;
