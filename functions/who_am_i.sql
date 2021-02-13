CREATE OR REPLACE FUNCTION who_am_i(
  OUT id integer, 
  OUT first_name text, 
  OUT last_name text,
  OUT title text,
  OUT phone text,
  OUT email text,
  OUT gender gender,
  OUT birth_date date,
  OUT date_of_employment date,
  OUT termination_date date,
  OUT address text,
  OUT postal_code text,
  OUT city text,
  OUT image_url text,
  OUT has_permanent_position boolean,
  OUT emoji emoji,
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
      gender,
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
  WHERE email = current_setting('request.jwt.claim.email')
$$; 
