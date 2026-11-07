-- Deploy floq:add_ledger_slack_threads to pg
-- requires: add_ledger_expenses
-- requires: add_ledger_social_events

BEGIN;

-- The post an expense was announced in, null when it was not: its ts, which names it to Slack and
-- which a correction or deletion replies under, and its text, which a correction sends back with a
-- note that the thread has the update.
ALTER TABLE ledger_expense
    ADD COLUMN slack_ts   TEXT,
    ADD COLUMN slack_text TEXT;

-- An event's first post, which closing it again after a reopen replies under.
ALTER TABLE ledger_social_event ADD COLUMN slack_ts TEXT;

COMMIT;
