-- Deploy floq:add_employee_user to pg

BEGIN;

-- Set password before deploying and then remember to NOT COMMIT the change!
CREATE USER employee PASSWORD NULL;
GRANT ALL PRIVILEGES ON SCHEMA public TO employee;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public to employee;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public to employee;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public to employee;
GRANT ALL PRIVILEGES ON DATABASE floq TO employee;

GRANT employee TO root;

COMMIT;
