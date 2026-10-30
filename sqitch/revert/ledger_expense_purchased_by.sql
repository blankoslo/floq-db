-- Revert floq:ledger_expense_purchased_by from pg

BEGIN;

-- Restored as the API wrote it, the caller, which is purchased_by. Rows imported from the old
-- sheets had none, and get one here.
ALTER TABLE ledger_expense ADD COLUMN created_by INTEGER REFERENCES employees (id);
UPDATE ledger_expense SET created_by = purchased_by;

ALTER TABLE ledger_expense RENAME CONSTRAINT ledger_expense_purchased_by_fkey TO ledger_expense_paid_by_fkey;
ALTER TABLE ledger_expense RENAME COLUMN purchased_by TO paid_by;

COMMIT;
