-- Revert floq:add_view_available_projects from pg

BEGIN;

DROP VIEW available_projects;

COMMIT;
