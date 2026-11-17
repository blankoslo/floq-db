-- Revert floq:share_ledger_event_utlegg_between_expenses from pg

BEGIN;

-- Two expenses on one utlegg cannot both keep it, so stop rather than lose one.
DO
$$
BEGIN
    IF EXISTS (
        SELECT tripletex_expense_id
        FROM ledger_social_event_expense
        WHERE tripletex_expense_id IS NOT NULL
        GROUP BY tripletex_expense_id
        HAVING count(*) > 1
    ) OR EXISTS (
        SELECT tripletex_expense_id
        FROM ledger_fagutvikling_event_expense
        WHERE tripletex_expense_id IS NOT NULL
        GROUP BY tripletex_expense_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'an utlegg is shared by more than one event expense';
    END IF;
END;
$$;

DROP INDEX ledger_social_event_expense_tripletex_expense_id_index;
ALTER TABLE ledger_social_event_expense
    ADD CONSTRAINT ledger_social_event_expense_tripletex_expense_id_key UNIQUE (tripletex_expense_id);

DROP INDEX ledger_fagutvikling_event_expense_tripletex_expense_id_index;
ALTER TABLE ledger_fagutvikling_event_expense
    ADD CONSTRAINT ledger_fagutvikling_event_expense_tripletex_expense_id_key UNIQUE (tripletex_expense_id);

COMMIT;
