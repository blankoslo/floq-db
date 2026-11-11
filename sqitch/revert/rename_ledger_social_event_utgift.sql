-- Revert floq:rename_ledger_social_event_utgift from pg

BEGIN;

ALTER TABLE ledger_social_event_expense
    RENAME CONSTRAINT ledger_social_event_expense_amount_positive TO ledger_social_event_utgift_amount_positive;
ALTER TABLE ledger_social_event_expense
    RENAME CONSTRAINT ledger_social_event_expense_tripletex_expense_id_key
    TO ledger_social_event_utgift_tripletex_expense_id_key;
ALTER TABLE ledger_social_event_expense
    RENAME CONSTRAINT ledger_social_event_expense_added_by_fkey TO ledger_social_event_utgift_added_by_fkey;
ALTER TABLE ledger_social_event_expense
    RENAME CONSTRAINT ledger_social_event_expense_event_id_fkey TO ledger_social_event_utgift_event_id_fkey;
ALTER TABLE ledger_social_event_expense
    RENAME CONSTRAINT ledger_social_event_expense_pkey TO ledger_social_event_utgift_pkey;

ALTER TABLE ledger_social_event_expense RENAME TO ledger_social_event_utgift;

COMMIT;
