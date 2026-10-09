-- gender and emoji are TEXT, not the gender enum / emoji domain: this keeps both
-- free for sqitch to alter or rebuild without a hard dependency reaching in from
-- this file. CREATE OR REPLACE cannot change an OUT parameter's type, so the
-- function is dropped first; harmless to leave in, since nothing depends on it.
DROP FUNCTION IF EXISTS who_am_i();
CREATE FUNCTION who_am_i(
  OUT id integer,
  OUT first_name text,
  OUT last_name text,
  OUT title text,
  OUT phone text,
  OUT email text,
  OUT gender text,
  OUT birth_date date,
  OUT date_of_employment date,
  OUT termination_date date,
  OUT address text,
  OUT postal_code text,
  OUT city text,
  OUT image_url text,
  OUT has_permanent_position boolean,
  OUT emoji text,
  OUT role text,
  OUT bio text
)
RETURNS record LANGUAGE sql AS $$
  SELECT
      id,
      first_name,
      last_name,
      title,
      phone,
      email,
      gender::text,
      birth_date,
      date_of_employment,
      termination_date,
      address,
      postal_code,
      city,
      image_url,
      has_permanent_position,
      emoji,
      role,
      bio
  FROM employees
  WHERE email = current_setting('request.jwt.claims')::json->>'email'
$$;
