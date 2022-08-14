-- Revert floq:add_trak_read_only_user from pg

BEGIN;

DROP USER IF EXISTS trak_read_only;

COMMIT;
