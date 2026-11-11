-- Deploy floq:add_ledger_fagutvikling_event_annet to pg
-- requires: add_ledger_fagutvikling_events

BEGIN;

-- Rebuilt rather than ADD VALUE: a label added in a transaction cannot be used in it, and the
-- checks below compare cost to it. Nothing but the cost column uses the type.
ALTER TYPE ledger_fagutvikling_cost RENAME TO ledger_fagutvikling_cost_old;

CREATE TYPE ledger_fagutvikling_cost AS ENUM ('ticket', 'travel', 'accommodation', 'annet');

ALTER TABLE ledger_fagutvikling_event_expense
    ALTER COLUMN cost TYPE ledger_fagutvikling_cost USING cost::TEXT::ledger_fagutvikling_cost;

DROP TYPE ledger_fagutvikling_cost_old;

-- An annet is what a sosialt event's utgift is: a receipt and its own utlegg, or typed in by hand
-- when Blank paid, with no utlegg and added_by whoever typed it. Billett, reise and kost og losji
-- stay receipts.
ALTER TABLE ledger_fagutvikling_event_expense
    ALTER COLUMN tripletex_expense_id DROP NOT NULL,
    -- Tripletex's cost category an annet's utlegg was booked under, by name, as on
    -- ledger_annet_expense.
    ADD COLUMN cost_category TEXT,
    ADD CONSTRAINT ledger_fagutvikling_event_expense_utlegg_or_annet
        CHECK (tripletex_expense_id IS NOT NULL OR cost = 'annet'),
    ADD CONSTRAINT ledger_fagutvikling_event_expense_cost_category_on_annet_utlegg
        CHECK ((cost_category IS NOT NULL) = (cost = 'annet' AND tripletex_expense_id IS NOT NULL));

COMMIT;
