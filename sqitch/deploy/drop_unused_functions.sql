-- Deploy floq:drop_unused_functions to pg

BEGIN;

-- floq-kpi is gone, and floq-platform has taken over balance, reports, timesheet and
-- staffing reads, so nothing calls these any more. The live callers left in
-- functions/ are floq-platform (company absence) and floq-cli (who_am_i,
-- projects_info_for_employee_in_period). The same functions leave functions/, so
-- deploy.sh cannot bring them back. DROP FUNCTION without CASCADE, so a view or
-- policy still depending on one stops the deploy instead of going with it.
DO $$
DECLARE
    routine regprocedure;
BEGIN
    FOR routine IN
        SELECT p.oid::regprocedure
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = ANY (ARRAY[
              'accumulated_billed_hours', 'accumulated_date_periods', 'accumulated_entries_on_project',
              'accumulated_hours_for_employee', 'accumulated_overtime_for_employee',
              'accumulated_reconciliation', 'all_absence_dates_in_period',
              'all_employee_work_dates_in_period', 'availability_percentage', 'available_dates_new',
              'billable_hours_for_employees', 'bonus_hours_for_employee', 'business_hours',
              'employee_has_sick_child_days', 'employees_roles', 'entries_sums_for_employee',
              'entries_sums_for_employee_with_project', 'fg', 'fg_bonus_employee_monthly',
              'fg_bonus_employee_monthly_range', 'fg_bonus_employee_weekly', 'fg_employee_period',
              'fg_employee_weekly', 'fg_for_employee', 'get_confirmed_avspasering_weeks',
              'get_employees_in_dates', 'get_latest_invoice_lock_events', 'hours_per_employee',
              'hours_per_project', 'is_date_in_week', 'kpi_accumulated_fg', 'kpi_accumulated_ot',
              'kpi_fg', 'kpi_prodev', 'kpi_product_development', 'kpi_sick', 'kpi_ul', 'kpi_visibility',
              'lock_employee_hours', 'lock_employee_hours_for_projects', 'month_dates',
              'monthly_balance_summary', 'nonbillable_hours_for_employees',
              'number_of_employees_in_period', 'ot', 'ot_rolling', 'product_development_hours',
              'sick_hours', 'sum_business_hours', 'time_distribution', 'time_tracking_status',
              'total_hours_on_project_in_period', 'unaccompanied_customer_involvement_in_period',
              'unaccompanied_customer_involvement_kpi', 'unavailable_absence_days_for_employees',
              'unavailable_hours_for_employees', 'unavailable_time_entry_hours', 'unregistered_days',
              'upsert_expense', 'upsert_invoice_balance', 'upsert_invoice_status', 'upsert_write_off',
              'week_dates', 'weekly_availability_json'])
    LOOP
        EXECUTE format('DROP FUNCTION %s', routine);
    END LOOP;
END
$$;

COMMIT;
