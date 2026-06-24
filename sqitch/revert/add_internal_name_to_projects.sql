-- Revert floq:add_internal_name_to_projects from pg

BEGIN;

ALTER TABLE projects
DROP COLUMN internal_name;

COMMIT;
