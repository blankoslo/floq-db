-- Deploy floq:alter_table_employees_add_emoji_column to pg

BEGIN;

-- The emoji domain lives here rather than functions/ because this column
-- needs it to exist before it can be created; a clean deploy can't rely on
-- functions/ having run first. Guarded since Postgres has no CREATE DOMAIN
-- IF NOT EXISTS/OR REPLACE and already-deployed environments have this
-- domain from when it lived in functions/emoji_domain.sql.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'emoji' AND typnamespace = 'public'::regnamespace) THEN
    CREATE DOMAIN emoji AS VARCHAR(10)
    CHECK (
    array_length(regexp_split_to_array(VALUE, '\s*'), 1) = 1 AND
    (
    '[128, 687]'::int4range @> ascii(VALUE)
    OR '[768, 1023]'::int4range @> ascii(VALUE)
    OR '[1536, 1791]'::int4range @> ascii(VALUE)
    OR '[3072, 3199]'::int4range @> ascii(VALUE)
    OR '[7616, 7679]'::int4range @> ascii(VALUE)
    OR '[7680, 7935]'::int4range @> ascii(VALUE)
    OR '[8192, 8351]'::int4range @> ascii(VALUE)
    OR '[8400, 8527]'::int4range @> ascii(VALUE)
    OR '[8592, 9215]'::int4range @> ascii(VALUE)
    OR '[9312, 9727]'::int4range @> ascii(VALUE)
    OR '[9728, 10223]'::int4range @> ascii(VALUE)
    OR '[10496, 10751]'::int4range @> ascii(VALUE)
    OR '[11008, 11263]'::int4range @> ascii(VALUE)
    OR '[11360, 11391]'::int4range @> ascii(VALUE)
    OR '[11776, 11903]'::int4range @> ascii(VALUE)
    OR '[12288, 12351]'::int4range @> ascii(VALUE)
    OR '[42128, 42191]'::int4range @> ascii(VALUE)
    OR '[57344, 63743]'::int4range @> ascii(VALUE)
    OR '[65024, 65039]'::int4range @> ascii(VALUE)
    OR '[65072, 65103]'::int4range @> ascii(VALUE)
    OR '[126976, 127023]'::int4range @> ascii(VALUE)
    OR '[127136, 127231]'::int4range @> ascii(VALUE)
    OR '[127232, 128591]'::int4range @> ascii(VALUE)
    OR '[128640, 128767]'::int4range @> ascii(VALUE)
    OR '[129296, 129387]'::int4range @> ascii(VALUE)
    OR '[129408, 129504]'::int4range @> ascii(VALUE) )
    );
  END IF;
END
$$;

ALTER TABLE employees
    ADD COLUMN emoji EMOJI;

COMMIT;
