-- Verify floq:alter_reference_and_comment_to_projects on pg

BEGIN;

SELECT tripletex_reference, tripletex_comment FROM projects LIMIT 1;

ROLLBACK;
