BEGIN;

DROP INDEX IF EXISTS time_entry_date_index;
DROP INDEX IF EXISTS time_entry_employee_date_index;

CREATE INDEX time_entry_date_index
    ON time_entry
    USING brin (date);

COMMIT;
