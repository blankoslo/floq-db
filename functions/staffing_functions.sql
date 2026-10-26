-- Deploy floq:absence_view to pg
-- requires: norwegian_holidays_to_2018
-- requires: staffing_table
-- requires: employees_table

BEGIN;

-- is_holiday is defined in sqitch (absence_table migration), not here, since
-- a CHECK constraint there needs it to exist before functions/ has run.
CREATE OR REPLACE FUNCTION is_weekday(d date)
        RETURNS boolean AS
$$
BEGIN
  RETURN NOT (    EXTRACT(dow FROM d) = 0
               OR EXTRACT(dow FROM d) = 6
             );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION week_dates(in_year integer, in_week integer)
RETURNS TABLE ( date date ) AS
$$
BEGIN
  RETURN QUERY SELECT date_trunc('week', (in_year::text || '-1-4')::timestamp)::date
    + 7 * (in_week - 1)  -- fix off-by-one
    + generate_series (0, 6);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION is_date_in_week(in_date date, in_year integer, in_week integer)
RETURNS boolean AS
$$
BEGIN
  RETURN (    EXTRACT(YEAR FROM in_date) = in_year
          AND EXTRACT(WEEK FROM in_date) = in_week
         );
END
$$ LANGUAGE plpgsql;

COMMIT;
