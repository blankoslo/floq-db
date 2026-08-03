-- Verify floq:add_tripletex_attn_id_to_projects on pg

BEGIN;

SELECT tripletex_attn_id FROM projects;

ROLLBACK;
