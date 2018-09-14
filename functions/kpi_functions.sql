CREATE OR REPLACE FUNCTION kpi_fg(in_start_date date, in_end_date date)
RETURNS TABLE (
  from_date date,
  to_date date,
  fg double precision
) AS
$$
BEGIN
  RETURN QUERY (

SELECT
  x.from_date,
  x.to_date,                                      
  100*(actual.sum_billable_hours / actual.sum_available_hours) AS fg
FROM
  (
    SELECT * from month_dates(in_start_date, in_end_date, interval '6' month)
  ) x,
   accumulated_billed_hours2(x.from_date, x.to_date) actual
  );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION kpi_product_development(in_start_date date, in_end_date date)
RETURNS TABLE (
 from_date date,
 to_date date,
 payload numeric
) AS
$$
BEGIN
 RETURN QUERY (
SELECT
 x.from_date,
 x.to_date,
 hours
FROM
 (
   SELECT * from month_dates(in_start_date, in_end_date, interval '6' month)
 ) AS x, 
   product_development_hours(x.from_date, x.to_date) AS hours   
GROUP BY x.from_date, x.to_date, hours.hours
);
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION kpi_sick(in_from_date date, in_to_date date)
RETURNS TABLE (
 from_date date,
 to_date date,
 payload double precision
) AS
$$
BEGIN
 RETURN QUERY (
SELECT
 x.from_date,
 x.to_date,
 sick_hours / sum_business_hours
FROM
 (
   SELECT * from month_dates(in_from_date, in_to_date, interval '6' month)
 ) AS x, 
 sum_business_hours(x.from_date, x.to_date),
 sick_hours(x.from_date, x.to_date)
GROUP BY x.from_date, x.to_date, sum_business_hours, sick_hours
);
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION kpi_ul(in_from_date date, in_to_date date)
RETURNS TABLE (
 from_date date,
 to_date date,
 payload double precision
) AS
$$
BEGIN
 RETURN QUERY (
SELECT
 x.from_date,
 x.to_date,
 sum(subcontractor_money) / sum(invoice_balance_money)
FROM
 (
   SELECT * from month_dates(in_from_date, in_to_date, interval '6' month)
 ) AS x, 
   hours_per_project(x.from_date, x.to_date) AS hours_per_project   
GROUP BY x.from_date, x.to_date
);
END
$$ LANGUAGE plpgsql;





///HELPERS
CREATE OR REPLACE FUNCTION sum_business_hours(in_from_date date, in_to_date date)
RETURNS TABLE (
	sum_business_hours double precision
) AS
$$
BEGIN
  RETURN QUERY (

SELECT
	sum(tt.business_hours)
FROM
  (
  	SELECT 
      business_hours 
    FROM 
		(
			SELECT 
        employees.id AS id,
        employees.first_name,
        employees.date_of_employment,
        employees.termination_date
      FROM
        employees,
        time_entry
			WHERE 
        time_entry.employee = employees.id AND
        time_entry.date <= in_to_date AND
        time_entry.date >= in_from_date
			GROUP BY 
        employees.id,
        employees.date_of_employment,
        employees.termination_date
		) AS e,
		business_hours(greatest(in_from_date, e.date_of_employment),least(e.termination_date, in_to_date))
  ) tt  
 );
END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION accumulated_staffing_hours2(from_date date, to_date date)
RETURNS TABLE (available_hours double precision, billable_hours numeric) AS
$$
BEGIN
  RETURN QUERY (
    SELECT
      sum_business_hours - unavailable_hours :: double precision AS sum_available_hours,
      (7.5 * count(*)):: numeric AS billable_hours
    FROM 
      sum_business_hours(from_date, to_date), 
      unavailable_staffing_hours(from_date, to_date),
      staffing
    JOIN projects ON
      projects.id = staffing.project AND
      projects.billable = 'billable' AND
      staffing.date <= to_date AND
      staffing.date >= from_date
    GROUP BY (sum_business_hours, unavailable_hours) LIMIT 1);
END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION accumulated_billed_hours2(from_date date, to_date date)
RETURNS TABLE (sum_available_hours double precision, sum_billable_hours numeric) AS
$$
BEGIN
  RETURN QUERY (
    SELECT
         sum_business_hours - unavailable_hours :: double precision AS sum_available_hours,
         SUM(minutes/60.0)  :: numeric AS sum_billable_hours
    FROM 
     sum_business_hours(from_date, to_date), 
     unavailable_time_entry_hours(from_date, to_date),
     time_entry
    JOIN projects ON
      projects.id = time_entry.project AND
      projects.billable = 'billable' AND
      time_entry.date <= to_date and time_entry.date >= from_date 
    GROUP BY (sum_business_hours, unavailable_hours)) LIMIT 1;
END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION unavailable_time_entry_hours(in_from_date date, in_to_date date)
RETURNS TABLE (
	unavailable_hours numeric
) AS
$$
BEGIN
  RETURN QUERY (

SELECT
	tt.unavailable
FROM
  (
	select sum(minutes/60.0) AS unavailable from projects join time_entry on time_entry.project = projects.id where projects.billable='unavailable'	and time_entry.date >= in_from_date and time_entry.date <= in_to_date 
  ) tt  
 );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION month_dates(in_from_date date, in_to_date date, in_interval interval)
RETURNS TABLE ( to_date DATE, from_date DATE) AS
$$
BEGIN
  RETURN QUERY select date_trunc('DAY', monat - interval '1' day)::DATE, date_trunc('MONTH', monat - in_interval)::DATE from 
    (select * from generate_series(date_trunc('MONTH', in_from_date), date_trunc('MONTH', in_to_date),'1 month') AS monat) AS mt order by 1;
    END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION unavailable_staffing_hours(start_date date, end_date date)
RETURNS TABLE (
  unavailable_hours numeric
) AS
$$
BEGIN
  RETURN QUERY (

SELECT
  tt.unavailable
FROM
  (
    SELECT
      7.5 * count(*) AS unavailable
    FROM
      staffing 
    JOIN projects ON
      staffing.project = projects.id
    WHERE 
      billable='unavailable' AND
      staffing.date <= end_date AND
      staffing.date >= start_date
  ) tt  
 );
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION sick_hours(start_date date, end_date date)
RETURNS TABLE (
sick_hours numeric
) AS
$$
BEGIN
  RETURN QUERY (

SELECT
  tt.sick
FROM
  (
    SELECT
      sum(minutes)/60.0 AS sick
    FROM
      time_entry
    WHERE
      (project = 'SYK1000' OR project = 'SYK1001' OR project = 'SYK1002') AND
      (time_entry.date >= start_date AND time_entry.date <= end_date)
  ) tt  
 );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION product_development_hours(from_date date, to_date date)
RETURNS TABLE (
hours numeric
) AS
$$
BEGIN
  RETURN QUERY (
    SELECT
      sum(minutes)/60.0 AS hours 
    FROM
      time_entry
    WHERE
      (project = 'INT1000' OR project = 'INT1004' OR project = 'INT1003') AND
      (time_entry.date >= from_date AND time_entry.date <= to_date)
 );
END
$$ LANGUAGE plpgsql;

/// Professional Development KPI

CREATE OR REPLACE FUNCTION public.total_hours_on_project_in_period(start_date date, end_date date, project_code text)
RETURNS TABLE(project_hours double precision)
LANGUAGE plpgsql
STABLE STRICT
AS $function$
begin
 return query (
   SELECT
    sum(minutes)/60::double precision AS project_hours
   FROM 
    time_entry
   WHERE
    time_entry.project = project_code AND
    time_entry.date BETWEEN start_date AND end_date
 );
end
$function$;


CREATE OR REPLACE FUNCTION public.prodev(start_date date, end_date date)
  RETURNS TABLE(date date, percent double precision)
AS $function$
begin
  return query (
    SELECT d.date, ((f.project_hours / p.available_hours)*100)::double precision AS percent FROM generate_series(
      start_date::date,
      end_date,
      '1 month'
  ) d, 
    accumulated_staffing_hours2((d.date - interval '6' month)::DATE, d.date) p, 
    total_hours_on_project_in_period((d.date - interval '6' month)::DATE, d.date, 'FAG1000') f
  );
end
$function$;

/// FG Deviation

CREATE OR REPLACE FUNCTION planned_billable_hours_in_period(start_date date, end_date date)
  RETURNS TABLE(date date, hours double precision)
AS $function$
begin
  return query (
    SELECT
      start_date::date,
      (SUM(spw.days) * 7.5)::double precision AS hours
    FROM staffing_per_week AS spw, projects AS p
    WHERE spw.project_id = p.id and p.billable = 'billable' 
    and to_date('' || spw.year || '-' || spw.week || '-1', 'IYYY-IW-ID') >= start_date
    and to_date('' || spw.year || '-' || spw.week || '-5', 'IYYY-IW-ID') <= end_date
  );
end
$function$;


CREATE OR REPLACE FUNCTION public.fgdev(start_date date, end_date date)
  RETURNS TABLE(org_date date, adj_date date, predicted_fg double precision, achieved_fg double precision, deviation_percent double precision)
AS $function$
begin
  return query (
    SELECT
      d.org_date::date AS org_date,
      d.adj_date::date AS adj_date,
      (pbh.hours/ash.available_hours)*100::double precision AS predicted_fg,
      (abh.sum_billable_hours/abh.sum_available_hours)*100::double precision AS achieved_fg,
      ((abh.sum_billable_hours/abh.sum_available_hours)/(pbh.hours/ash.available_hours))*100-100 AS deviation_percent
    FROM
      (
        SELECT
          dd AS org_date,
          (dd - ((SELECT CASE WHEN wd = 6 THEN 0 ELSE wd END FROM date_part('dow', dd) AS wd) || ' day')::INTERVAL) AS adj_date
        FROM 
          generate_series(start_date::timestamp, end_date::timestamp, '1 month') AS dd
      ) d,
      planned_billable_hours_in_period((d.adj_date::date - interval '12 week')::DATE, d.adj_date::date) pbh,
      accumulated_staffing_hours2((d.adj_date::date - interval '12 week')::DATE, d.adj_date::date) ash,
      accumulated_billed_hours2((d.adj_date::date - interval '12 week')::DATE, d.adj_date::date) abh
  );
end
$function$;

// VISIBILITY

CREATE OR REPLACE FUNCTION public.visibility(start_date date, end_date date)
  RETURNS TABLE(org_date date, fwd_adj_date date, percent double precision)
AS $function$
begin
  return query (
    SELECT
      d.org_date::DATE,
      d.fwd_adj_date::DATE,
      (pbh.hours/ash.available_hours)*100::double precision AS forecasted_fg
    FROM
    (
      SELECT
        date_i AS org_date,
        (date_i + ((7 - date_part('dow', date_i)) || ' day')::INTERVAL) AS fwd_adj_date 
      FROM
        generate_series(start_date::timestamp, end_date::timestamp, '1 month') AS date_i
    ) d,
    planned_billable_hours_in_period(d.fwd_adj_date::DATE, (d.fwd_adj_date + interval '12 weeks')::DATE) pbh,
    accumulated_staffing_hours2(d.fwd_adj_date::DATE, (d.fwd_adj_date + interval '12 weeks')::DATE) ash
    
  );
end
$function$;
