-- Deploy floq:create_project_members_table to pg
-- requires: employees_table
-- requires: time_tracking_tables

BEGIN;

CREATE TABLE project_members (
  employee_id integer NOT NULL REFERENCES employees(id),
  customer_id text    NOT NULL REFERENCES customers(id),
  hourly_rate numeric NOT NULL,
  from_date   date    NOT NULL,
  PRIMARY KEY (employee_id, customer_id, from_date)
);

GRANT ALL PRIVILEGES ON TABLE project_members TO employee;

COMMIT;
