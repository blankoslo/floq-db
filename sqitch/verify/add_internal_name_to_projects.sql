-- Verify floq:add_internal_name_to_projects on pg

BEGIN;

SELECT internal_name FROM projects

ROLLBACK;
