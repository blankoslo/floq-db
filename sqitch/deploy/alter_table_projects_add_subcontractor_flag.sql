-- Deploy floq:alter_table_projects_add_subcontractor_flag to pg
-- requires: time_tracking_tables

BEGIN;

ALTER TABLE projects
  ADD COLUMN has_subcontractor_consultants boolean NOT NULL DEFAULT false,
  ADD COLUMN is_subcontractor              boolean NOT NULL DEFAULT false;

COMMIT;
