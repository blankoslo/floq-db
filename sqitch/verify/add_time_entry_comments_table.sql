-- Verify floq:add_time_entry_comments_table on pg

BEGIN;

SELECT * FROM time_entry_comments;

-- divide-by-zero if policy does not exist
SELECT 1/COUNT(*) FROM pg_catalog.pg_policies WHERE tablename = 'time_entry_comments';

ROLLBACK;
