-- Deploy floq:rename_staffing_to_daily_staffing to pg
-- requires: staffing_table
-- requires: update_view_employee_project_responsible
-- requires: alter_table_absence_add_percentage
-- requires: backfill_staffing_week
-- requires: add_employee_user

BEGIN;

-- Staffing is staffing_week, and nothing reads or writes the per-date table any more.
-- It is kept, read-only, as daily_staffing for its history. The functions that used it
-- are dropped; they live in functions/ and would otherwise fail at their next call.
-- The views are dropped rather than left to follow the rename.
DROP VIEW employee_project_responsible;
DROP VIEW staffed_hours;

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
              'accumulated_staffing_hours', 'add_staffing', 'add_staffing_in_period',
              'apply_weekly_staffing', 'available_dates', 'company_week_base', 'company_week_codes',
              'company_week_forward', 'employee_worked_days_per_week', 'employees_on_projects',
              'fix_staffing_on_weekends_and_holidays', 'forcasted_available_hours',
              'forcasted_fg_in_period', 'get_employee_period_hours', 'get_periodic_report',
              'get_weekly_staffing_dates', 'get_weekly_staffing_json', 'insert_staffing',
              'is_possible_work_day', 'kpi_fgdev', 'overbooked_weeks', 'planned_billable_hours',
              'plan_weekly_staffing', 'possible_work_dates_per_employee',
              'projects_for_employee_for_date', 'remove_staffing', 'remove_staffing_in_period',
              'restore_weekly_staffing', 'staffed_billable_hours_for_employees',
              'staffed_nonbillable_hours_for_employees', 'staffing_and_billing_overview',
              'staffing_days_to_points', 'staffing_points_to_days', 'time_tracking_status_by_week',
              'time_tracking_status_with_staffing', 'unavailable_staffing_hours',
              'unavilable_staffing_dates_in_period', 'upsert_staffing', 'upsert_weekly_staffing',
              'weekday_dates', 'weekly_fg_json', 'weekly_forecasted_fg_json',
              'worked_days_per_week', 'write_weekly_staffing_points'])
    LOOP
        EXECUTE format('DROP FUNCTION %s', routine);
    END LOOP;
END
$$;

ALTER TABLE staffing RENAME TO daily_staffing;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE daily_staffing FROM employee;

COMMIT;
