-- Deploy floq:add_time_entry_comments_table to pg
-- requires: time_tracking_tables
-- requires: enable_employee_row_level_security

BEGIN;

CREATE TABLE time_entry_comments (
    id       TEXT PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee INTEGER NOT NULL REFERENCES employees(id),
    creator  INTEGER NOT NULL REFERENCES employees(id),
    comment  TEXT NOT NULL,
    project  TEXT NOT NULL REFERENCES projects(id),
    date     DATE NOT NULL,
    created  TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
    UNIQUE (employee, project, date)
);

GRANT ALL PRIVILEGES ON TABLE time_entry_comments TO employee;

SELECT enable_default_row_level_security('time_entry_comments', 'check_employee_write_access(employee)');

COMMIT;
