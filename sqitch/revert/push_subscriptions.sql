-- Revert floq:add_push_subscriptions_table from pg

BEGIN;

DROP TABLE IF EXISTS push_subscriptions;

COMMIT;