-- Revert floq:remove_to_date_and_project_id_from_project_members from pg

BEGIN;

ALTER TABLE project_members
  ADD COLUMN to_date   date,
  ADD COLUMN project_id text REFERENCES projects(id);

COMMIT;
