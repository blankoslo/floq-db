-- Deploy floq:add_paid_overtime_employee_paid_date_index to pg
-- requires: paid_overtime_table

BEGIN;

CREATE INDEX paid_overtime_employee_paid_date_index
    ON paid_overtime
    USING btree (employee, paid_date);

COMMIT;
