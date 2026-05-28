-- Revert floq:create_project_members_table from pg

BEGIN;

DROP TABLE project_members;

COMMIT;
