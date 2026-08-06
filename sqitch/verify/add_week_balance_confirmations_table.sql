-- Verify floq:add_week_balance_confirmations_table on pg

BEGIN;

SELECT id, employee, creator, week_start, minutes, confirmed, created FROM week_balance_confirmations;

ROLLBACK;
