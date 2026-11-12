-- Revert floq:allow_ledger_fagutvikling_event_expense_without_utlegg from pg

BEGIN;

-- A billett, reise or kost og losji Blank paid has no utlegg to give it, so stop rather than lose it.
DO
$$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM ledger_fagutvikling_event_expense
        WHERE tripletex_expense_id IS NULL
          AND cost <> 'annet'
    ) THEN
        RAISE EXCEPTION 'ledger_fagutvikling_event_expense has rows Blank paid that are not annet';
    END IF;
END;
$$;

ALTER TABLE ledger_fagutvikling_event_expense
    ADD CONSTRAINT ledger_fagutvikling_event_expense_utlegg_or_annet
        CHECK (tripletex_expense_id IS NOT NULL OR cost = 'annet');

COMMIT;
