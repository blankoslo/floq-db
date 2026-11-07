-- Revert floq:add_ledger_slack_threads from pg

BEGIN;

ALTER TABLE ledger_social_event DROP COLUMN slack_ts;

ALTER TABLE ledger_expense
    DROP COLUMN slack_text,
    DROP COLUMN slack_ts;

COMMIT;
