-- Deploy floq:alter_projects_table to pg

BEGIN;

ALTER TABLE projects
  ADD COLUMN tripletex_contact_id integer;


COMMIT;
