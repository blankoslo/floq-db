-- Revert floq:alter_table_absence_add_percentage from pg

BEGIN;

DROP VIEW staffed_hours;

ALTER TABLE absence
    DROP CONSTRAINT absence_pkey,
    DROP COLUMN percentage,
    ADD PRIMARY KEY (employee_id, date);

COMMIT;
