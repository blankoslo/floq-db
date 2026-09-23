BEGIN;

DELETE FROM employee_role WHERE role_type::TEXT = 'salg';

ALTER TYPE employee_role_type RENAME TO employee_role_type_with_salg;

CREATE TYPE employee_role_type AS ENUM ('admin');

ALTER TABLE employee_role
    ALTER COLUMN role_type TYPE employee_role_type USING role_type::TEXT::employee_role_type;

DROP TYPE employee_role_type_with_salg;

COMMIT;
