-- Revert floq:alter_table_staffing_add_staffing_percentage from pg

BEGIN;

DROP CONSTRAINT staffing_pkey;
DROP COLUMN percentage;
ADD PRIMARY KEY staffing pkey(employee, date);

COMMIT;
