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



CREATE OR REPLACE FUNCTION kpi_ot(in_from_date date, in_to_date date)
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
  sum(invoice_balance_money) / (sum(invoice_balance_minutes)/60.0)
FROM
  (
    SELECT * from month_dates(in_from_date, in_to_date)
  ) as x,	
  	hours_per_project(x.from_date, x.to_date) as hours_per_project
  	
GROUP BY x.from_date, x.to_date
);
END
$$ LANGUAGE plpgsql;






CREATE OR REPLACE FUNCTION kpi_ot(in_from_date date, in_to_date date)
RETURNS TABLE (
 from_date date,
 to_date date,
 imoney double precision,
 payload double precision
) AS
$$
BEGIN
 RETURN QUERY (
SELECT
 x.from_date,
 x.to_date,
 sum(invoice_balance_money), 
 ot                   
FROM
 (
   SELECT * from month_dates(in_from_date, in_to_date, interval '1' month)
 ) as x, 
   hours_per_project(x.from_date, x.to_date) as hours_per_project,
   (sum(invoice_balance_money) - sum(subcontractor_money) - sum(expense_money)) / ((sum(invoice_balance_minutes))/60.0) as ot
   
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
  	select business_hours from 
		(
			select employees.id as id, employees.first_name, employees.date_of_employment, employees.termination_date from employees,
			time_entry
			where time_entry.employee = employees.id
			and time_entry.date <= in_to_date and time_entry.date >= in_from_date
			group by employees.id, employees.date_of_employment, employees.termination_date
		) as e,
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
         7.5 * count(*)  :: numeric AS billable_hours
       FROM 
        sum_business_hours(from_date, to_date), 
      unavailable_staffing_hours(from_date, to_date),
      staffing join projects on projects.id = staffing.project and projects.billable = 'billable' and staffing.date <= to_date and staffing.date >= from_date 
      group by (sum_business_hours, unavailable_hours) LIMIT 1);
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
      unavailable_hours(from_date, to_date),
      time_entry join projects on projects.id = time_entry.project and projects.billable = 'billable' and date <= to_date and date >= from_date 
      group by (sum_business_hours, unavailable_hours)) LIMIT 1;
END
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION unavailable_hours(in_from_date date, in_to_date date)
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
	select sum(minutes/60.0) as unavailable from projects join time_entry on time_entry.project = projects.id where projects.billable='unavailable'	and time_entry.date >= in_from_date and time_entry.date <= in_to_date 
  ) tt  
 );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION month_dates(in_from_date date, in_to_date date, in_interval interval)
RETURNS TABLE ( to_date DATE, from_date DATE) AS
$$
BEGIN
  RETURN QUERY select date_trunc('DAY', monat - interval '1' day)::DATE, date_trunc('MONTH', monat - in_interval)::DATE from 
    (select * from generate_series(date_trunc('MONTH', in_from_date), date_trunc('MONTH', in_to_date),'1 month') as monat) as mt order by 1;
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
  select 7.5 * count(*) as unavailable from staffing join projects on staffing.project = projects.id where billable='unavailable' and staffing.date <= end_date and staffing.date >= start_date
  ) tt  
 );
END
$$ LANGUAGE plpgsql;