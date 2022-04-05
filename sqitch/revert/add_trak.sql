-- Revert floq:add_trak from pg

BEGIN;

DROP TYPE responsible_type CASCADE;

DROP TABLE IF EXISTS employee_settings CASCADE;
DROP TABLE IF EXISTS employee_task CASCADE;
DROP TABLE IF EXISTS employee_task_comments CASCADE;
DROP TABLE IF EXISTS notification CASCADE;
DROP TABLE IF EXISTS phase CASCADE;
DROP TABLE IF EXISTS process_template CASCADE;
DROP TABLE IF EXISTS profession CASCADE;
DROP TABLE IF EXISTS profession_task CASCADE;
DROP TABLE IF EXISTS task CASCADE;

ALTER TABLE employees
    DROP profession_id,
    DROP CONSTRAINT employee_hr_manager_fkey;

DROP INDEX IF EXISTS employee_email_key CASCADE;

COMMIT;
