-- Revert floq:add_ledger_fagutvikling_events from pg

BEGIN;

-- An arrangement, and the attendees, expenses and shares that hang off it, have no other place to
-- go, so stop rather than lose them.
DO
$$
BEGIN
    IF EXISTS (SELECT 1 FROM ledger_fagutvikling_event) THEN
        RAISE EXCEPTION 'ledger_fagutvikling_event has rows';
    END IF;
END;
$$;

DROP TABLE ledger_fagutvikling_event_expense_share;
DROP TABLE ledger_fagutvikling_event_expense;
DROP TABLE ledger_fagutvikling_event_attendee;
DROP TABLE ledger_fagutvikling_event;

DROP TYPE ledger_fagutvikling_cost;

COMMIT;
