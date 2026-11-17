-- Deploy floq:share_ledger_event_utlegg_between_expenses to pg
-- requires: rename_ledger_social_event_utgift
-- requires: allow_ledger_fagutvikling_event_expense_without_utlegg

BEGIN;

-- The receipts added to an event in one save go on one utlegg, one expense each. The platform still
-- refuses an utlegg recorded by an earlier save, under its lock.
ALTER TABLE ledger_social_event_expense
    DROP CONSTRAINT ledger_social_event_expense_tripletex_expense_id_key;
CREATE INDEX ledger_social_event_expense_tripletex_expense_id_index
    ON ledger_social_event_expense (tripletex_expense_id);

ALTER TABLE ledger_fagutvikling_event_expense
    DROP CONSTRAINT ledger_fagutvikling_event_expense_tripletex_expense_id_key;
CREATE INDEX ledger_fagutvikling_event_expense_tripletex_expense_id_index
    ON ledger_fagutvikling_event_expense (tripletex_expense_id);

COMMIT;
