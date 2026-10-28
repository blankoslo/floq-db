-- Revert floq:add_ledger_expenses from pg

BEGIN;

DROP TABLE ledger_receipt;
DROP TABLE ledger_expense_draft;
DROP TABLE ledger_fagutvikling_participant;
DROP TABLE ledger_fagutvikling_expense;
DROP TABLE ledger_social_expense;
DROP TABLE ledger_tech_expense;
DROP TABLE ledger_expense;

DROP FUNCTION ledger_expense_editable(TEXT);
DROP FUNCTION ledger_expense_visible(TEXT);
DROP FUNCTION set_ledger_created_by();

DROP TYPE ledger_expense_type;

COMMIT;
