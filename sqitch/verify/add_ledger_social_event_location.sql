-- Verify floq:add_ledger_social_event_location on pg

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ledger_social_event'
          AND column_name = 'location'
          AND data_type = 'text'
          AND is_nullable = 'YES'
    ) THEN
        RAISE EXCEPTION 'ledger_social_event should have a nullable text location';
    END IF;
END $$;
