-- Revert floq:add_project_pins from pg

BEGIN;

DROP TABLE project_code_pins;

COMMIT;
