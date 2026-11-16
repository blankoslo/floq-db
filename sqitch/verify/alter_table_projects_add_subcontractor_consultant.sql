-- Verify floq:alter_table_projects_add_subcontractor_consultant on pg

DO $$
BEGIN
    IF (
        SELECT count(*)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'projects'
          AND is_nullable = 'YES'
          AND (
               (column_name = 'subcontractor_consultant_name' AND data_type = 'text')
            OR (column_name = 'subcontractor_hourly_rate' AND data_type = 'numeric'
                AND numeric_precision = 10 AND numeric_scale = 2)
            OR (column_name = 'subcontractor_margin' AND data_type = 'numeric'
                AND numeric_precision = 5 AND numeric_scale = 2)
          )
    ) <> 3 THEN
        RAISE EXCEPTION 'projects should have nullable subcontractor_consultant_name text, subcontractor_hourly_rate numeric(10,2) and subcontractor_margin numeric(5,2)';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.projects'::regclass
          AND conname = 'projects_subcontractor_consultant_only_when_flagged'
    ) THEN
        RAISE EXCEPTION 'projects should refuse subcontractor consultant fields when has_subcontractor_consultants is false';
    END IF;
END $$;
