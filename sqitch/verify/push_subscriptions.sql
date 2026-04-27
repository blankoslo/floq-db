-- Verify floq:add_push_subscriptions_table on pg

BEGIN;

SELECT * FROM push_subscriptions;

ROLLBACK;