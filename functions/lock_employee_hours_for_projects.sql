CREATE OR REPLACE FUNCTION public.lock_employee_hours_for_projects(in_projects text[],
                                                                    in_start date,
                                                                    in_end date,
                                                                    in_commit date,
                                                                    in_creator integer)
    RETURNS void
AS
$function$
BEGIN
    INSERT INTO timelock_events (creator, employee, commit_date)
    SELECT DISTINCT in_creator, te.employee, in_commit
    FROM time_entry AS te
    WHERE te.project = ANY(in_projects)
      AND te.date >= in_start
      AND te.date <= in_end
      AND NOT EXISTS(
            SELECT *
            FROM (SELECT *
                  FROM timelock_events
                  WHERE employee = te.employee
                  ORDER BY created DESC
                  LIMIT 1) AS latest_event
            WHERE latest_event.commit_date = in_commit
        );
END;
$function$ LANGUAGE plpgsql
