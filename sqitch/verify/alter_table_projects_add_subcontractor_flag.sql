-- Verify floq:alter_table_projects_add_subcontractor_flag on pg

BEGIN;

SELECT has_subcontractor_consultants, is_subcontractor FROM projects;

ROLLBACK;
