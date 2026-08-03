-- Revert floq:add_tripletex_attn_id_to_projects from pg

BEGIN;

ALTER TABLE projects
  DROP COLUMN tripletex_attn_id;

COMMIT;
