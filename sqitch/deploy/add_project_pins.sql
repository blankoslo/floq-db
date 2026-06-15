-- Deploy floq:add_project_pins to pg

BEGIN;

CREATE TABLE project_code_pins (
  id            SERIAL PRIMARY KEY,
  employee_id   INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  pin_type      TEXT NOT NULL CHECK (pin_type IN ('favorite', 'week')),
  week          DATE,          -- NULL for favorites; Monday of the week for 'week' pins
  created       TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE NULLS NOT DISTINCT (employee_id, project_id, pin_type, week)
);

GRANT ALL PRIVILEGES ON TABLE project_code_pins TO employee;
GRANT USAGE, SELECT ON SEQUENCE project_code_pins_id_seq TO employee;

COMMIT;
