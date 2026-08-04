-- Verify floq:remove_to_date_and_project_id_from_project_members on pg

BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'project_members'
          AND column_name IN ('to_date', 'project_id')
    ) THEN
        RAISE EXCEPTION 'to_date/project_id columns still exist on project_members';
    END IF;
END $$;

ROLLBACK;
