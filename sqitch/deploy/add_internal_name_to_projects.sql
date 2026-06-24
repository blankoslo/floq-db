-- Deploy floq:add_internal_name_to_projects to pg

BEGIN;

ALTER TABLE projects
ADD COLUMN internal_name text;

COMMIT;
