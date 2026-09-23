BEGIN;

DO
$$
BEGIN
    IF NOT 'salg' = ANY (enum_range(NULL::employee_role_type)::TEXT[]) THEN
        RAISE EXCEPTION 'employee_role_type has no salg value';
    END IF;
END;
$$;

ROLLBACK;
