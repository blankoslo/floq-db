-- Deploy floq:alter_reference_and_comment_to_projects to pg

BEGIN;

ALTER TABLE projects ADD COLUMN tripletex_reference text;
ALTER TABLE projects ADD COLUMN tripletex_comment text;

COMMIT;
