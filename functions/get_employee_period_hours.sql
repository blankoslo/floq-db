-- Sparse per (employee, project, day) hours + staffing over a date range.
-- in_employee_ids NULL means every employee; scope selection (role, self, all)
-- is the caller's job, this function is a plain projection.
--
-- It exists because floq-dashboard's company/role-wide views cannot use
-- floq-reports-api's /invoice/project-summary: that endpoint is per project, and
-- each call cross joins generate_series(days) against every employee on the
-- project and every other project those employees touched. Asking it for the
-- whole company means hundreds of such queries.
--
-- Rounding is deliberately identical to floq-reports-api's getProjectSummary
-- (InvoiceQueries.kt): round to one decimal per employee/project/day and sum
-- downstream, so the per-customer view and the company/role views can never
-- disagree by a rounding step.
--
-- NOT STRICT: in_employee_ids IS NULL is a meaningful argument, and a STRICT
-- function would silently return no rows for the whole-company scope.

DROP FUNCTION IF EXISTS public.get_employee_period_hours(integer[], date, date);

CREATE OR REPLACE FUNCTION public.get_employee_period_hours(in_employee_ids integer[],
                                                            in_start_date date,
                                                            in_end_date date)
    RETURNS TABLE(
        employee_id         integer,
        employee_name       text,
        project_id          text,
        project_name        text,
        billable            text,
        entry_date          date,
        hours               double precision,
        staffing_percentage integer
    )
    LANGUAGE sql
    STABLE
    PARALLEL SAFE
AS
$function$
    WITH entries AS (
        SELECT te.employee AS emp,
               te.project  AS proj,
               te.date     AS day,
               coalesce(round(sum(te.minutes) / 60.0, 1), 0)::float8 AS hours,
               0 AS pct
        FROM time_entry te
        WHERE te.date >= in_start_date
          AND te.date <= in_end_date
          AND (in_employee_ids IS NULL OR te.employee = ANY (in_employee_ids))
        GROUP BY te.employee, te.project, te.date
    ),
    staffed AS (
        -- Staffed-but-unlogged is the signal behind "Timer mangler", so an
        -- employee with staffing and no time entries must still produce rows.
        SELECT st.employee   AS emp,
               st.project    AS proj,
               st.date       AS day,
               0::float8     AS hours,
               st.percentage AS pct
        FROM staffing st
        WHERE st.date >= in_start_date
          AND st.date <= in_end_date
          AND (in_employee_ids IS NULL OR st.employee = ANY (in_employee_ids))
    ),
    combined AS (
        -- staffing's primary key is (employee, project, date), so max(pct)
        -- picks the single real percentage over the 0 from the entries branch.
        SELECT u.emp, u.proj, u.day,
               sum(u.hours)::float8 AS hours,
               max(u.pct)           AS pct
        FROM (SELECT * FROM entries UNION ALL SELECT * FROM staffed) u
        GROUP BY u.emp, u.proj, u.day
    )
    SELECT c.emp,
           e.first_name || ' ' || e.last_name,
           c.proj,
           p.name,
           p.billable::text,
           c.day,
           c.hours,
           c.pct
    FROM combined c
    JOIN employees e ON e.id = c.emp
    JOIN projects  p ON p.id = c.proj
    -- Sparse on purpose: the caller densifies over the requested range. Note
    -- projects are not filtered on `active` — a closed project still carries
    -- the month's hours.
    WHERE c.hours > 0 OR c.pct > 0
$function$;
