-- Deploy floq:grant_select_to_employee_and_read_only_on_profession to pg
-- requires: add_trak
-- requires: add_employee_user
-- requires: add_read_only_user

BEGIN;

-- profession was added by add_trak but outlives it: it still constrains
-- employees.profession_id, independent of the rest of the (now otherwise
-- unused) Trak schema. Grant it like any other table, per the read_only
-- convention established in grant_select_to_read_only_on_missing_tables.

GRANT SELECT ON TABLE profession TO employee;
GRANT SELECT ON TABLE profession TO read_only;

COMMIT;
