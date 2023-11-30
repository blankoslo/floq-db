-- Deploy floq:remove_trak to pg

BEGIN;

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
    
DROP TYPE responsible_type CASCADE;

DROP INDEX IF EXISTS employee_email_key CASCADE;

DROP EXTENSION IF EXISTS pgcrypto;

COMMIT;
