-- Revert floq:alter_projects_table from pg

BEGIN;

ALTER TABLE projects DROP COLUMN IF EXISTS tripletex_contact_id;

COMMIT;
