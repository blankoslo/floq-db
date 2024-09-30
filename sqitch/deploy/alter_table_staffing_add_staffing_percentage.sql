-- Deploy floq:alter_table_staffing_add_staffing_percentage to pg

BEGIN;

ALTER TABLE staffing
    DROP CONSTRAINT staffing_pkey,
    ADD COLUMN percentage INT NOT NULL DEFAULT 100,
    ADD PRIMARY KEY (employee, date, percentage);

COMMIT;
