-- Verify floq:allow_ledger_fagutvikling_event_expense_without_utlegg on pg

BEGIN;

DO
$$
BEGIN
    IF (
        SELECT array_agg(conname::TEXT || ':' || contype::TEXT ORDER BY conname)
        FROM pg_catalog.pg_constraint
        WHERE conrelid = 'ledger_fagutvikling_event_expense'::regclass
          AND contype IN ('c', 'u')
    ) IS DISTINCT FROM ARRAY[
        'ledger_fagutvikling_event_expense_amount_positive:c',
        'ledger_fagutvikling_event_expense_cost_category_on_annet_utlegg:c',
        'ledger_fagutvikling_event_expense_tripletex_expense_id_key:u'
    ] THEN
        RAISE EXCEPTION 'any cost may lack an utlegg, and only an annet''s utlegg has a cost category';
    END IF;
END;
$$;

ROLLBACK;
