-- Revert floq:alter_table_projects_add_subcontractor_consultant from pg

BEGIN;

ALTER TABLE projects
  DROP CONSTRAINT projects_subcontractor_consultant_only_when_flagged,
  DROP COLUMN subcontractor_margin,
  DROP COLUMN subcontractor_hourly_rate,
  DROP COLUMN subcontractor_consultant_name;

COMMIT;
