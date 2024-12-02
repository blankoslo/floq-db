    -- Deploy floq:alter_table_absence_add_percentage to pg

BEGIN;

ALTER TABLE absence
    DROP CONSTRAINT absence_pkey,
    ADD COLUMN percentage INT NOT NULL DEFAULT 100,
    ADD PRIMARY KEY (employee_id,reason,date);

COMMIT;
