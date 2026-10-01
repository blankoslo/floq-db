-- Verify floq:grant_select_to_employee_and_read_only_on_profession on pg

BEGIN;

SET ROLE employee;
SELECT * FROM profession WHERE false;
RESET ROLE;

SET ROLE read_only;
SELECT * FROM profession WHERE false;
RESET ROLE;

ROLLBACK;
