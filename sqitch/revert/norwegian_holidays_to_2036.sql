-- Revert floq:norwegian_holidays_to_2036 from pg

BEGIN;

-- Takes the whole window back out, including any row this change found already
-- there and left alone. Nothing in this window predates the change in a
-- deployed database, so that is the same set.
DELETE FROM holidays
WHERE "date" >= '2026-12-24' AND "date" <= '2037-01-01';

COMMIT;
