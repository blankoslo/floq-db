-- Deploy floq:add_staffing_events to pg
-- requires: staffing_table
-- requires: alter_table_staffing_add_staffing_percentage
-- requires: add_read_only_user
-- requires: enable_employee_row_level_security

BEGIN;

-- staffing holds the current plan only, so nothing in floq can answer what the plan said eight
-- weeks ago. This log is the answer, from the day it is deployed: one row per change, never
-- updated, never deleted. No foreign keys, because a log that a later delete can block is not a log.
CREATE TABLE staffing_events (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee    INTEGER NOT NULL,
    project     TEXT NOT NULL,
    date        DATE NOT NULL,
    percentage  INTEGER NOT NULL,
    action      TEXT NOT NULL CHECK (action IN ('insert', 'update', 'delete')),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX staffing_events_recorded_at_idx ON staffing_events (recorded_at);
CREATE INDEX staffing_events_date_idx ON staffing_events (date);

GRANT SELECT ON TABLE staffing_events TO employee;
GRANT SELECT ON TABLE staffing_events TO read_only;

-- No write grant and a write policy that is never true: only the trigger appends, and it appends
-- as the owner.
SELECT enable_default_row_level_security('staffing_events', 'false');

CREATE FUNCTION log_staffing_event()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public, pg_temp
AS
$$
DECLARE
    logged staffing%ROWTYPE := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
BEGIN
    INSERT INTO staffing_events (employee, project, date, percentage, action)
    VALUES (logged.employee, logged.project, logged.date, logged.percentage, lower(TG_OP));

    RETURN NULL;
END;
$$;

CREATE TRIGGER staffing_event
    AFTER INSERT OR UPDATE OR DELETE ON staffing
    FOR EACH ROW
EXECUTE FUNCTION log_staffing_event();

COMMIT;
