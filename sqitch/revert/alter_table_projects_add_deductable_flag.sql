-- Revert floq:alter_table_projects_add_skattefunn_flag from pg

BEGIN;

ALTER TABLE projects
    DROP COLUMN deductable;

COMMIT;
