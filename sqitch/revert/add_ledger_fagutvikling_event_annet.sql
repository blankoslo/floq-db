-- Revert floq:add_ledger_fagutvikling_event_annet from pg

BEGIN;

-- The label cannot go while an expense has it, and an annet has no other cost to become, so stop
-- rather than lose it.
DO
$$
BEGIN
    IF EXISTS (SELECT 1 FROM ledger_fagutvikling_event_expense WHERE cost = 'annet') THEN
        RAISE EXCEPTION 'ledger_fagutvikling_event_expense has annet rows';
    END IF;
END;
$$;

ALTER TABLE ledger_fagutvikling_event_expense
    DROP CONSTRAINT ledger_fagutvikling_event_expense_cost_category_on_annet_utlegg,
    DROP CONSTRAINT ledger_fagutvikling_event_expense_utlegg_or_annet,
    DROP COLUMN cost_category,
    ALTER COLUMN tripletex_expense_id SET NOT NULL;

ALTER TYPE ledger_fagutvikling_cost RENAME TO ledger_fagutvikling_cost_old;

CREATE TYPE ledger_fagutvikling_cost AS ENUM ('ticket', 'travel', 'accommodation');

ALTER TABLE ledger_fagutvikling_event_expense
    ALTER COLUMN cost TYPE ledger_fagutvikling_cost USING cost::TEXT::ledger_fagutvikling_cost;

DROP TYPE ledger_fagutvikling_cost_old;

COMMIT;
