-- Revert floq:add_read_only_user from pg

BEGIN;

DROP USER IF EXISTS read_only;

COMMIT;
