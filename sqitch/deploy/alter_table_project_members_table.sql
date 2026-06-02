-- Deploy floq:alter_table_project_members_table to pg
-- requires: create_project_members_table
-- requires: time_tracking_tables

BEGIN;

ALTER TABLE project_members
  ADD COLUMN to_date   date,
  ADD COLUMN project_id text REFERENCES projects(id);

COMMIT;
