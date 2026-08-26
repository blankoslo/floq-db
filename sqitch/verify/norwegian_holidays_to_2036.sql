-- Verify floq:norwegian_holidays_to_2036 on pg

BEGIN;

-- 197 rows across the window 2026-12-24 .. 2037-01-01: 66 de-facto days (six
-- per Christmas closure, 2026 through 2036) and 131 red days (13 a year, 12 in
-- 2027 and 2032 where 17. mai is 2. pinsedag, plus the partial years at each
-- end of the window).
SELECT 1/(COUNT(*) = 197)::int
  FROM holidays
 WHERE "date" >= '2026-12-24' AND "date" <= '2037-01-01';

-- No working day may survive inside a Christmas closure: every date from
-- 12-24 through the following 01-01 must be present, for every closure the
-- window covers whole.
SELECT 1/(COUNT(*) = 0)::int FROM (
  SELECT d::date
    FROM generate_series('2026-12-24'::date, '2037-01-01'::date, '1 day') AS d
   WHERE (EXTRACT(month FROM d) = 12 AND EXTRACT(day FROM d) >= 24)
      OR (EXTRACT(month FROM d) = 1  AND EXTRACT(day FROM d) = 1)
  EXCEPT
  SELECT "date" FROM holidays
) AS gaps;

ROLLBACK;
