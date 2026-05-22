-- Revert floq:alter_table_projects_add_subcontractor_flag from pg

BEGIN;

ALTER TABLE projects
  DROP COLUMN has_subcontractor_consultants,
  DROP COLUMN is_subcontractor;

COMMIT;
