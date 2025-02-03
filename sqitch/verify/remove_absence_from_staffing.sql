DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM staffing
        JOIN absence_reasons 
            ON staffing.project = absence_reasons.id
    ) THEN
        RAISE EXCEPTION 'There are still rows in staffing with a matching project';
    END IF;

    RAISE NOTICE 'Verification successful: no matching rows remain in staffing.';
END $$;
