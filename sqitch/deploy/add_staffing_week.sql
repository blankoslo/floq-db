-- Deploy floq:add_staffing_week to pg
-- requires: absence_table
-- requires: add_employee_user
-- requires: add_read_only_user

BEGIN;

-- Staffing as decided: a share of a person's working time on a project, per ISO
-- week. The share is of the week's working days - weekdays that are not public
-- holidays and fall within the person's employment - so 100 in a week with two
-- holidays is three days. Absence does not shorten it. Replaces the per-date
-- `staffing` table, which is written alongside this one until every reader has
-- moved over.
CREATE TABLE staffing_week (
    employee   INTEGER      NOT NULL REFERENCES employees(id) ON UPDATE CASCADE,
    project    TEXT         NOT NULL REFERENCES projects(id)  ON UPDATE CASCADE,
    week_start DATE         NOT NULL,
    -- Four decimals so a value typed in hours survives the round trip:
    -- 32.5 hours of a 37.5-hour week is 86.6667.
    percentage NUMERIC(7,4) NOT NULL,

    CONSTRAINT staffing_week_week_start_is_monday CHECK (EXTRACT(ISODOW FROM week_start) = 1),
    CONSTRAINT staffing_week_percentage_check CHECK (percentage > 0 AND percentage <= 100),
    CONSTRAINT staffing_week_not_absence CHECK (NOT is_absence_reason(project)),
    PRIMARY KEY (employee, week_start, project)
);

CREATE INDEX staffing_week_week_start_idx ON staffing_week (week_start);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE staffing_week TO employee;
GRANT SELECT ON TABLE staffing_week TO read_only;

COMMIT;
