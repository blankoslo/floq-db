-- Verify floq:alter_projects_table on pg

BEGIN;

SELECT tripletex_contact_id FROM projects LIMIT 1;

ROLLBACK;
