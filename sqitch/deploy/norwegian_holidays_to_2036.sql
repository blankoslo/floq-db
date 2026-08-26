-- Deploy floq:norwegian_holidays_to_2036 to pg
-- requires: holidays_table

-- Continues norwegian_holidays_to_2018: same two groups, same names, same
-- rules, later years. Every date in here is derived, not looked up.
--
--   fixed dates   01-01 · 05-01 · 05-17 · 12-25 · 12-26
--   from Easter   E-7 Palmesøndag · E-3 Skjærtorsdag · E-2 Langfredag
--                 E+0 1. påskedag · E+1 2. påskedag
--                 E+39 Kristi himmelfartsdag · E+49 1. pinsedag · E+50 2. pinsedag
--   de facto      12-24 Julaften · 12-27..12-30 Julefri · 12-31 Nyttårsaften
--
-- Easter Sundays used, by the Gregorian computus:
--   2027-03-28  2028-04-16  2029-04-01  2030-04-21  2031-04-13  2032-03-28
--   2033-04-17  2034-04-09  2035-03-25  2036-04-13
--
-- The range is a window, 2026-12-24 through 2037-01-01, not a set of whole
-- years. It starts and ends mid-Christmas-break on purpose: every day of every
-- closure in here is present, including the red days inside them, so no break
-- has a working day in the middle of it or a missing 1. nyttårsdag at the end.
--
-- Two things the 2018 seed never had to decide:
--   * 1. påskedag is included. The old seed listed Palmesøndag but not Easter
--     Sunday itself, which is the day the law names. Neither matters to the
--     current readers -- both drop weekends before consulting this table --
--     but the table should not disagree with the calendar.
--   * 17. mai falls on 2. pinsedag in 2027 and 2032. date is the primary key,
--     so those two dates carry both names rather than silently losing one.
--
-- ON CONFLICT DO NOTHING, so this survives a database where some of these
-- years were already filled in by hand. 2019-2026 stay empty apart from that
-- last Christmas break; filling years already behind us would rewrite hours
-- that have been invoiced.

BEGIN;

-- de-facto holidays:
-- Closed from Julaften through Nyttårsaften, the practice the 2017 rows
-- started. 1. and 2. juledag fall inside this closure but are law, not policy,
-- so they are in the section below.

INSERT INTO holidays (date, name) VALUES
  -- 2026
    ('2026-12-24', 'Julaften'),
    ('2026-12-27', 'Julefri'),
    ('2026-12-28', 'Julefri'),
    ('2026-12-29', 'Julefri'),
    ('2026-12-30', 'Julefri'),
    ('2026-12-31', 'Nyttårsaften'),
  -- 2027
    ('2027-12-24', 'Julaften'),
    ('2027-12-27', 'Julefri'),
    ('2027-12-28', 'Julefri'),
    ('2027-12-29', 'Julefri'),
    ('2027-12-30', 'Julefri'),
    ('2027-12-31', 'Nyttårsaften'),
  -- 2028
    ('2028-12-24', 'Julaften'),
    ('2028-12-27', 'Julefri'),
    ('2028-12-28', 'Julefri'),
    ('2028-12-29', 'Julefri'),
    ('2028-12-30', 'Julefri'),
    ('2028-12-31', 'Nyttårsaften'),
  -- 2029
    ('2029-12-24', 'Julaften'),
    ('2029-12-27', 'Julefri'),
    ('2029-12-28', 'Julefri'),
    ('2029-12-29', 'Julefri'),
    ('2029-12-30', 'Julefri'),
    ('2029-12-31', 'Nyttårsaften'),
  -- 2030
    ('2030-12-24', 'Julaften'),
    ('2030-12-27', 'Julefri'),
    ('2030-12-28', 'Julefri'),
    ('2030-12-29', 'Julefri'),
    ('2030-12-30', 'Julefri'),
    ('2030-12-31', 'Nyttårsaften'),
  -- 2031
    ('2031-12-24', 'Julaften'),
    ('2031-12-27', 'Julefri'),
    ('2031-12-28', 'Julefri'),
    ('2031-12-29', 'Julefri'),
    ('2031-12-30', 'Julefri'),
    ('2031-12-31', 'Nyttårsaften'),
  -- 2032
    ('2032-12-24', 'Julaften'),
    ('2032-12-27', 'Julefri'),
    ('2032-12-28', 'Julefri'),
    ('2032-12-29', 'Julefri'),
    ('2032-12-30', 'Julefri'),
    ('2032-12-31', 'Nyttårsaften'),
  -- 2033
    ('2033-12-24', 'Julaften'),
    ('2033-12-27', 'Julefri'),
    ('2033-12-28', 'Julefri'),
    ('2033-12-29', 'Julefri'),
    ('2033-12-30', 'Julefri'),
    ('2033-12-31', 'Nyttårsaften'),
  -- 2034
    ('2034-12-24', 'Julaften'),
    ('2034-12-27', 'Julefri'),
    ('2034-12-28', 'Julefri'),
    ('2034-12-29', 'Julefri'),
    ('2034-12-30', 'Julefri'),
    ('2034-12-31', 'Nyttårsaften'),
  -- 2035
    ('2035-12-24', 'Julaften'),
    ('2035-12-27', 'Julefri'),
    ('2035-12-28', 'Julefri'),
    ('2035-12-29', 'Julefri'),
    ('2035-12-30', 'Julefri'),
    ('2035-12-31', 'Nyttårsaften'),
  -- 2036
    ('2036-12-24', 'Julaften'),
    ('2036-12-27', 'Julefri'),
    ('2036-12-28', 'Julefri'),
    ('2036-12-29', 'Julefri'),
    ('2036-12-30', 'Julefri'),
    ('2036-12-31', 'Nyttårsaften')
ON CONFLICT DO NOTHING;

-- “real” holidays

INSERT INTO holidays (date, name) VALUES
  -- 2026
    ('2026-12-25', '1. juledag'),
    ('2026-12-26', '2. juledag'),
  -- 2027
    ('2027-01-01', '1. nyttårsdag'),
    ('2027-03-21', 'Palmesøndag'),
    ('2027-03-25', 'Skjærtorsdag'),
    ('2027-03-26', 'Langfredag'),
    ('2027-03-28', '1. påskedag'),
    ('2027-03-29', '2. påskedag'),
    ('2027-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2027-05-06', 'Kristi himmelfartsdag'),
    ('2027-05-16', '1. pinsedag'),
    ('2027-05-17', 'Grunnlovsdag / 2. pinsedag'),
    ('2027-12-25', '1. juledag'),
    ('2027-12-26', '2. juledag'),
  -- 2028
    ('2028-01-01', '1. nyttårsdag'),
    ('2028-04-09', 'Palmesøndag'),
    ('2028-04-13', 'Skjærtorsdag'),
    ('2028-04-14', 'Langfredag'),
    ('2028-04-16', '1. påskedag'),
    ('2028-04-17', '2. påskedag'),
    ('2028-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2028-05-17', 'Grunnlovsdag'),
    ('2028-05-25', 'Kristi himmelfartsdag'),
    ('2028-06-04', '1. pinsedag'),
    ('2028-06-05', '2. pinsedag'),
    ('2028-12-25', '1. juledag'),
    ('2028-12-26', '2. juledag'),
  -- 2029
    ('2029-01-01', '1. nyttårsdag'),
    ('2029-03-25', 'Palmesøndag'),
    ('2029-03-29', 'Skjærtorsdag'),
    ('2029-03-30', 'Langfredag'),
    ('2029-04-01', '1. påskedag'),
    ('2029-04-02', '2. påskedag'),
    ('2029-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2029-05-10', 'Kristi himmelfartsdag'),
    ('2029-05-17', 'Grunnlovsdag'),
    ('2029-05-20', '1. pinsedag'),
    ('2029-05-21', '2. pinsedag'),
    ('2029-12-25', '1. juledag'),
    ('2029-12-26', '2. juledag'),
  -- 2030
    ('2030-01-01', '1. nyttårsdag'),
    ('2030-04-14', 'Palmesøndag'),
    ('2030-04-18', 'Skjærtorsdag'),
    ('2030-04-19', 'Langfredag'),
    ('2030-04-21', '1. påskedag'),
    ('2030-04-22', '2. påskedag'),
    ('2030-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2030-05-17', 'Grunnlovsdag'),
    ('2030-05-30', 'Kristi himmelfartsdag'),
    ('2030-06-09', '1. pinsedag'),
    ('2030-06-10', '2. pinsedag'),
    ('2030-12-25', '1. juledag'),
    ('2030-12-26', '2. juledag'),
  -- 2031
    ('2031-01-01', '1. nyttårsdag'),
    ('2031-04-06', 'Palmesøndag'),
    ('2031-04-10', 'Skjærtorsdag'),
    ('2031-04-11', 'Langfredag'),
    ('2031-04-13', '1. påskedag'),
    ('2031-04-14', '2. påskedag'),
    ('2031-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2031-05-17', 'Grunnlovsdag'),
    ('2031-05-22', 'Kristi himmelfartsdag'),
    ('2031-06-01', '1. pinsedag'),
    ('2031-06-02', '2. pinsedag'),
    ('2031-12-25', '1. juledag'),
    ('2031-12-26', '2. juledag'),
  -- 2032
    ('2032-01-01', '1. nyttårsdag'),
    ('2032-03-21', 'Palmesøndag'),
    ('2032-03-25', 'Skjærtorsdag'),
    ('2032-03-26', 'Langfredag'),
    ('2032-03-28', '1. påskedag'),
    ('2032-03-29', '2. påskedag'),
    ('2032-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2032-05-06', 'Kristi himmelfartsdag'),
    ('2032-05-16', '1. pinsedag'),
    ('2032-05-17', 'Grunnlovsdag / 2. pinsedag'),
    ('2032-12-25', '1. juledag'),
    ('2032-12-26', '2. juledag'),
  -- 2033
    ('2033-01-01', '1. nyttårsdag'),
    ('2033-04-10', 'Palmesøndag'),
    ('2033-04-14', 'Skjærtorsdag'),
    ('2033-04-15', 'Langfredag'),
    ('2033-04-17', '1. påskedag'),
    ('2033-04-18', '2. påskedag'),
    ('2033-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2033-05-17', 'Grunnlovsdag'),
    ('2033-05-26', 'Kristi himmelfartsdag'),
    ('2033-06-05', '1. pinsedag'),
    ('2033-06-06', '2. pinsedag'),
    ('2033-12-25', '1. juledag'),
    ('2033-12-26', '2. juledag'),
  -- 2034
    ('2034-01-01', '1. nyttårsdag'),
    ('2034-04-02', 'Palmesøndag'),
    ('2034-04-06', 'Skjærtorsdag'),
    ('2034-04-07', 'Langfredag'),
    ('2034-04-09', '1. påskedag'),
    ('2034-04-10', '2. påskedag'),
    ('2034-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2034-05-17', 'Grunnlovsdag'),
    ('2034-05-18', 'Kristi himmelfartsdag'),
    ('2034-05-28', '1. pinsedag'),
    ('2034-05-29', '2. pinsedag'),
    ('2034-12-25', '1. juledag'),
    ('2034-12-26', '2. juledag'),
  -- 2035
    ('2035-01-01', '1. nyttårsdag'),
    ('2035-03-18', 'Palmesøndag'),
    ('2035-03-22', 'Skjærtorsdag'),
    ('2035-03-23', 'Langfredag'),
    ('2035-03-25', '1. påskedag'),
    ('2035-03-26', '2. påskedag'),
    ('2035-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2035-05-03', 'Kristi himmelfartsdag'),
    ('2035-05-13', '1. pinsedag'),
    ('2035-05-14', '2. pinsedag'),
    ('2035-05-17', 'Grunnlovsdag'),
    ('2035-12-25', '1. juledag'),
    ('2035-12-26', '2. juledag'),
  -- 2036
    ('2036-01-01', '1. nyttårsdag'),
    ('2036-04-06', 'Palmesøndag'),
    ('2036-04-10', 'Skjærtorsdag'),
    ('2036-04-11', 'Langfredag'),
    ('2036-04-13', '1. påskedag'),
    ('2036-04-14', '2. påskedag'),
    ('2036-05-01', 'Arbeidernes internasjonale kampdag'),
    ('2036-05-17', 'Grunnlovsdag'),
    ('2036-05-22', 'Kristi himmelfartsdag'),
    ('2036-06-01', '1. pinsedag'),
    ('2036-06-02', '2. pinsedag'),
    ('2036-12-25', '1. juledag'),
    ('2036-12-26', '2. juledag'),
  -- 2037
    ('2037-01-01', '1. nyttårsdag')
ON CONFLICT DO NOTHING;

COMMIT;
