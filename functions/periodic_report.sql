CREATE OR REPLACE FUNCTION public.get_periodic_report(start_date DATE, end_date DATE)
RETURNS TABLE (
  prosjekt TEXT,
  timer NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    monthly_report.project AS prosjekt, 
    CASE
      WHEN monthly_report.source = 'time_entry' THEN ROUND((monthly_report.minutes / 60.0)::NUMERIC, 2)
      ELSE monthly_report.minutes::NUMERIC
    END AS timer
  FROM (
    SELECT
      CASE
        WHEN t.project = 'FAG1000' THEN 'Fagutvikling'
        WHEN t.project = 'ADM1003' THEN 'Åremålsadmin'
        WHEN t.project LIKE 'INT%' THEN 'Internsystemer'
        WHEN t.project = 'PER1000' THEN 'Perm med lønn'
        WHEN t.project = 'REK1000' THEN 'Rekruttering'
        WHEN t.project = 'SYK1000' THEN 'Egenmelding'
        WHEN t.project = 'SYK1002' THEN 'Sykt barn'
        WHEN t.project = 'SYK1001' THEN 'Sykemelding'
        ELSE t.project
      END AS project,
      SUM(t.minutes)::NUMERIC AS minutes, 
      'time_entry' AS source
    FROM time_entry t
    WHERE t.date BETWEEN start_date AND end_date
      AND (
        t.project IN ('FAG1000', 'ADM1003', 'PER1000', 'REK1000', 'SYK1001', 'SYK1002', 'SYK1003')
        OR t.project LIKE 'INT%'
      )
    GROUP BY
      CASE
        WHEN t.project = 'FAG1000' THEN 'Fagutvikling'
        WHEN t.project = 'ADM1003' THEN 'Åremålsadmin'
        WHEN t.project LIKE 'INT%' THEN 'Internsystemer'
        WHEN t.project = 'PER1000' THEN 'Perm med lønn'
        WHEN t.project = 'REK1000' THEN 'Rekruttering'
        WHEN t.project = 'SYK1000' THEN 'Egenmelding'
        WHEN t.project = 'SYK1002' THEN 'Sykt barn'
        WHEN t.project = 'SYK1001' THEN 'Sykemelding'
        ELSE t.project
      END

    UNION ALL

    SELECT 'Sykdom (inkl barn)', SUM(t.minutes)::NUMERIC, 'time_entry'
    FROM time_entry t
    WHERE t.date BETWEEN start_date AND end_date
      AND t.project IN ('SYK1000', 'SYK1002')

    UNION ALL

    SELECT 'Foreldreperm', SUM(t.minutes)::NUMERIC, 'time_entry'
    FROM time_entry t
    WHERE t.date BETWEEN start_date AND end_date
      AND t.project IN ('PER1002', 'PER1003', 'PER1004')

    UNION ALL

    SELECT 'Ferie', SUM(t.minutes)::NUMERIC, 'time_entry'
    FROM time_entry t
    WHERE t.date BETWEEN start_date AND end_date
      AND t.project = 'FER1000'

    UNION ALL

    SELECT 'Fakturerbart', SUM(t.billable_hours)::NUMERIC, 'staffing'
    FROM time_tracking_status_with_staffing(start_date, end_date) t

    UNION ALL

    SELECT 'Totalt tilgjengelig', SUM(t.available_hours)::NUMERIC, 'staffing'
    FROM time_tracking_status_with_staffing(start_date, end_date) t

    UNION ALL

    SELECT 'Admin og Salg ført av admin/ledelse', SUM(t.minutes)::NUMERIC, 'time_entry'
    FROM time_entry t
    JOIN employees e ON e.id = t.employee
    WHERE e.role = 'Annet'
      AND t.date BETWEEN start_date AND end_date
      AND t.project IN ('ADM1000', 'SAL1000')

    UNION ALL

    SELECT 'Salg ført av andre', SUM(t.minutes)::NUMERIC, 'time_entry'
    FROM time_entry t
    JOIN employees e ON e.id = t.employee
    WHERE e.role <> 'Annet'
      AND t.date BETWEEN start_date AND end_date
      AND t.project = 'SAL1000'

    UNION ALL

    SELECT 'Admin ført av andre', SUM(t.minutes)::NUMERIC, 'time_entry'
    FROM time_entry t
    JOIN employees e ON e.id = t.employee
    WHERE e.role <> 'Annet'
      AND t.date BETWEEN start_date AND end_date
      AND t.project = 'ADM1000'
  ) AS monthly_report;
END;
$$ LANGUAGE plpgsql;