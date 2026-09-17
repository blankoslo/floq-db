-- Revert floq:alter_table_employees_add_emoji_column from pg

BEGIN;

ALTER TABLE employees
    DROP COLUMN emoji;

DROP DOMAIN emoji;

COMMIT;
