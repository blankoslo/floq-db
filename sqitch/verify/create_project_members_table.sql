-- Verify floq:create_project_members_table on pg

BEGIN;

SELECT id, consultant_id, project_id, hourly_rate, from_date, to_date FROM project_members;

ROLLBACK;
