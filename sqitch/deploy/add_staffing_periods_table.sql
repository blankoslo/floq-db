-- Deploy floq:add_staffing_periods_table to pg

BEGIN;

CREATE TABLE staffing_periods (
  employee INTEGER REFERENCES employees(id),
  project TEXT REFERENCES projects(id),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  percentage INTEGER NOT NULL CHECK (percentage >= 0 AND percentage <= 100)
);

CREATE UNIQUE INDEX idx_staffing_periods ON staffing_periods(employee, project, start_date);

COMMIT;
