-- Verify floq:create_project_members_table on pg

BEGIN;

SELECT employee_id, customer_id, hourly_rate, from_date FROM project_members;

ROLLBACK;
