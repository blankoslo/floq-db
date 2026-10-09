BEGIN;

DELETE FROM employee_role WHERE role_type::TEXT = 'salg';

ALTER TYPE employee_role_type RENAME TO employee_role_type_with_salg;

-- Rebuilt from whatever values are actually left, not a hardcoded ('admin'): a
-- later migration may have added more roles since this one deployed, and those
-- must survive this revert too.
DO
$$
DECLARE
    remaining_values TEXT;
BEGIN
    SELECT string_agg(quote_literal(enumlabel), ', ' ORDER BY enumsortorder)
    INTO remaining_values
    FROM pg_enum
    WHERE enumtypid = 'employee_role_type_with_salg'::regtype
      AND enumlabel <> 'salg';

    EXECUTE format('CREATE TYPE employee_role_type AS ENUM (%s)', remaining_values);
END
$$;

ALTER TABLE employee_role
    ALTER COLUMN role_type TYPE employee_role_type USING role_type::TEXT::employee_role_type;

DROP TYPE employee_role_type_with_salg;

COMMIT;
