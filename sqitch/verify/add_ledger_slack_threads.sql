-- Verify floq:add_ledger_slack_threads on pg

DO $$
BEGIN
    IF (
        SELECT count(*)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND data_type = 'text'
          AND is_nullable = 'YES'
          AND (table_name, column_name) IN (
              ('ledger_expense', 'slack_ts'),
              ('ledger_expense', 'slack_text'),
              ('ledger_social_event', 'slack_ts'))
    ) <> 3 THEN
        RAISE EXCEPTION 'ledger_expense should have nullable text slack_ts and slack_text, and ledger_social_event a nullable text slack_ts';
    END IF;
END $$;
