-- Deploy floq:allow_ledger_fagutvikling_event_expense_without_utlegg to pg
-- requires: add_ledger_fagutvikling_event_annet

BEGIN;

-- Any utgift on a fag arrangement may be typed in by hand when Blank paid, not only an annet. Only
-- an annet's utlegg still has a cost category.
ALTER TABLE ledger_fagutvikling_event_expense
    DROP CONSTRAINT ledger_fagutvikling_event_expense_utlegg_or_annet;

COMMIT;
