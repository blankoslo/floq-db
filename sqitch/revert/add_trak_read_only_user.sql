-- Revert floq:add_trak_read_only_user from pg

BEGIN;

REVOKE trak_read_only FROM root;
REVOKE ALL PRIVILEGES ON SCHEMA public FROM trak_read_only;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM trak_read_only;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM trak_read_only;
REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public FROM trak_read_only;
REVOKE ALL PRIVILEGES ON DATABASE floq FROM trak_read_only;
DROP USER IF EXISTS trak_read_only;

COMMIT;
