-- Deploy floq:ledger_expense_purchased_by to pg
-- requires: add_ledger_expenses

BEGIN;

-- It holds who bought it. Who paid follows from tripletex_expense_id: with an utlegg the buyer
-- was reimbursed, without one Blank paid.
ALTER TABLE ledger_expense RENAME COLUMN paid_by TO purchased_by;
ALTER TABLE ledger_expense RENAME CONSTRAINT ledger_expense_paid_by_fkey TO ledger_expense_purchased_by_fkey;

-- The ledger API always wrote the caller into both, so it said nothing purchased_by does not.
ALTER TABLE ledger_expense DROP COLUMN created_by;

COMMIT;
