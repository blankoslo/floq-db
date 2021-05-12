-- Verify floq:add_read_only_user on pg

BEGIN;

-- divide-by-zero if user does not exist
SELECT 1/COUNT(*) FROM pg_catalog.pg_user
WHERE usename = 'read_only' AND passwd IS NOT NULL;

ROLLBACK;
