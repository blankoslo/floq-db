-- roles is TEXT[], not employee_role_type[]: Postgres serializes an enum array to
-- JSON as plain strings either way, so callers see no difference, but this keeps
-- employee_role_type free for sqitch to alter or rebuild without a hard dependency
-- reaching in from this file. CREATE OR REPLACE cannot change a return type, so
-- each overload is dropped first; harmless to leave in, since nothing depends on
-- these functions (DROP would otherwise fail and point that out).

DROP FUNCTION IF EXISTS public.employees_roles(INTEGER);
CREATE FUNCTION public.employees_roles(id_param INTEGER)
    RETURNS TABLE(employee employees, roles TEXT[])
    LANGUAGE SQL IMMUTABLE STRICT
AS $function$
    SELECT employees, array_remove(array_agg(role_type::TEXT), NULL) AS roles
    FROM employees LEFT OUTER JOIN employee_role ON (employees.id = employee_role.employee_id)
    WHERE employees.id = id_param
    GROUP BY employees.id
$function$;

DROP FUNCTION IF EXISTS public.employees_roles();
CREATE FUNCTION public.employees_roles()
    RETURNS TABLE(employee employees, roles TEXT[])
    LANGUAGE SQL IMMUTABLE STRICT
AS $function$
    SELECT employees_roles(employees.id)
    FROM employees
    ORDER BY employees.id
$function$;

DROP FUNCTION IF EXISTS public.employees_roles(TEXT);
CREATE FUNCTION public.employees_roles(email_param TEXT)
    RETURNS TABLE(employee employees, roles TEXT[])
    LANGUAGE SQL IMMUTABLE STRICT
AS $function$
    SELECT employees, array_remove(array_agg(role_type::TEXT), NULL) AS roles
    FROM employees LEFT OUTER JOIN employee_role ON (employees.id = employee_role.employee_id)
    WHERE employees.email = email_param
    GROUP BY employees.id
$function$;
