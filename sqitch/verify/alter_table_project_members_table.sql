-- Verify floq:alter_table_project_members_table on pg

BEGIN;

SELECT to_date, project_id FROM project_members;

ROLLBACK;
