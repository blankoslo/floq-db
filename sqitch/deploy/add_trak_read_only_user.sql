-- Deploy floq:add_trak_read_only_user to pg

BEGIN;

-- Set password before deploying and then remember to NOT COMMIT the change!
CREATE USER trak_read_only ENCRYPTED PASSWORD NULL;
GRANT SELECT ON TABLE employees TO trak_read_only;
GRANT SELECT ON TABLE profession TO trak_read_only;
GRANT SELECT ON TABLE projects TO trak_read_only;
GRANT SELECT ON TABLE staffing TO trak_read_only;

GRANT trak_read_only TO root;

COMMIT;
