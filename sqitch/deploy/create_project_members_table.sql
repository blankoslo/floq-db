-- Deploy floq:create_project_members_table to pg
-- requires: employees_table
-- requires: time_tracking_tables

BEGIN;

CREATE TABLE project_members (
  id          TEXT    CONSTRAINT project_members_pkey PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id integer NOT NULL REFERENCES employees(id),
  customer_id text    NOT NULL REFERENCES customers(id),
  hourly_rate numeric NOT NULL,
  from_date   date    NOT NULL
);

GRANT ALL PRIVILEGES ON TABLE project_members TO employee;

COMMIT;
