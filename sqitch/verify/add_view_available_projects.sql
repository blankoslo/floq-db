-- Verify floq:add_view_available_projects on pg

BEGIN;

SELECT * FROM available_projects WHERE false;

ROLLBACK;
