-- Revert floq:add_week_balance_confirmations_table from pg

BEGIN;

DROP TABLE week_balance_confirmations;

COMMIT;
