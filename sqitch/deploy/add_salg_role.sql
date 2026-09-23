BEGIN;

ALTER TYPE employee_role_type ADD VALUE IF NOT EXISTS 'salg';

COMMIT;
