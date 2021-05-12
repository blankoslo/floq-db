-- Deploy floq:add_read_only_user to pg

BEGIN;

-- Set password before deploying and then remember to NOT COMMIT the change!
CREATE USER read_only ENCRYPTED PASSWORD NULL;
GRANT SELECT ON ALL TABLES IN SCHEMA public to read_only;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public to read_only;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public to read_only;

GRANT read_only TO root;

COMMIT;
