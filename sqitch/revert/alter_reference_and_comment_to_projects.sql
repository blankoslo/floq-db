-- Revert floq:alter_reference_and_comment_to_projects from pg

BEGIN;

ALTER TABLE projects DROP COLUMN IF EXISTS tripletex_reference;
ALTER TABLE projects DROP COLUMN IF EXISTS tripletex_comment;

COMMIT;
