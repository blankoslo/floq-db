-- Revert floq:alter_table_staffing_add_staffing_percentage from pg

BEGIN;

ALTER TABLE staffing
    DROP CONSTRAINT staffing_pkey,
    DROP COLUMN percentage,
    ADD PRIMARY KEY (employee, date);

COMMIT;
