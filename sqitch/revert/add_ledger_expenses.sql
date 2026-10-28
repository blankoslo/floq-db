-- Revert floq:add_ledger_expenses from pg

BEGIN;

DROP TABLE ledger_fagutvikling_participant;
DROP TABLE ledger_fagutvikling_expense;
DROP TABLE ledger_social_expense;
DROP TABLE ledger_tech_expense;
DROP TABLE ledger_expense;

DROP TYPE ledger_expense_type;

COMMIT;
