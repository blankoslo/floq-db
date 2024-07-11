BEGIN;

DROP INDEX IF EXISTS time_entry_date_index;

CREATE INDEX time_entry_date_index
    ON time_entry
    USING btree (date);

CREATE INDEX time_entry_employee_date_index
    ON time_entry
    USING btree (employee, date);

COMMIT;
