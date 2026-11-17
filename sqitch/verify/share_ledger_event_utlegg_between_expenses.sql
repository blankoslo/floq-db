-- Verify floq:share_ledger_event_utlegg_between_expenses on pg

BEGIN;

DO
$$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conrelid IN ('ledger_social_event_expense'::regclass, 'ledger_fagutvikling_event_expense'::regclass)
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION 'an utlegg can still be on only one event expense';
    END IF;

    IF to_regclass('public.ledger_social_event_expense_tripletex_expense_id_index') IS NULL
        OR to_regclass('public.ledger_fagutvikling_event_expense_tripletex_expense_id_index') IS NULL THEN
        RAISE EXCEPTION 'event expenses are not indexed by their utlegg';
    END IF;
END;
$$;

ROLLBACK;
