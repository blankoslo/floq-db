-- Deploy floq:remove_to_date_and_project_id_from_project_members to pg
-- requires: alter_table_project_members_table

BEGIN;

ALTER TABLE project_members
  DROP COLUMN to_date,
  DROP COLUMN project_id;

COMMIT;
