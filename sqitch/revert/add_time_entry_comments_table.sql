-- Revert floq:add_time_entry_comments_table from pg

BEGIN;

DROP POLICY IF EXISTS time_entry_comments_select_policy ON time_entry_comments;
DROP POLICY IF EXISTS time_entry_comments_write_policy ON time_entry_comments;
DROP TABLE IF EXISTS time_entry_comments;

COMMIT;
