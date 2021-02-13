CREATE OR REPLACE FUNCTION who_am_i()
RETURNS TABLE(
    id integer, 
    first_name text, 
    last_name text,
    title text,
    phone text,
    email text,
    gender gender,
    birth_date date,
    date_of_employment date,
    termination_date date,
    address text,
    postal_code text,
    city text,
    image_url text,
    has_permanent_position boolean,
    emoji emoji,
    role text,
    bio text
) 
LANGUAGE sql IMMUTABLE STRICT AS 
$function$
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
$function$