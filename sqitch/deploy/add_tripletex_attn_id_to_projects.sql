-- Deploy floq:add_tripletex_attn_id_to_projects to pg

BEGIN;

ALTER TABLE projects
  ADD COLUMN tripletex_attn_id integer;

COMMIT;
