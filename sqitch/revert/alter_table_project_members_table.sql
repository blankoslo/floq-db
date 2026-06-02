-- Revert floq:alter_table_project_members_table from pg

BEGIN;

ALTER TABLE project_members
  DROP COLUMN to_date,
  DROP COLUMN project_id;

COMMIT;
