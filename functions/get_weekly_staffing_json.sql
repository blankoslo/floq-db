CREATE OR REPLACE FUNCTION public.get_weekly_staffing_json (start_date date, end_date date)
	RETURNS jsonb
	LANGUAGE plpgsql
	STRICT
	AS $function$
DECLARE
	result JSONB;
BEGIN
	SELECT
		jsonb_agg(jsonb_build_object ('id', e.employee_id, 'name', concat_ws(' ', e.first_name, e.last_name), 'role', e.role, 'imageUrl', e.image_url, 'subRows', COALESCE(s.subrows, '[]'::jsonb))
		ORDER BY
			e.first_name, e.last_name) INTO result
	FROM
		public.get_employees_in_dates (start_date,
			end_date) e
	LEFT JOIN (WITH joined_data AS (
			SELECT
				s.employee AS id,
				s.project AS name,
				s.date AS joined_date,
				s.percentage AS percentage,
				p.billable AS billable,
				p.name AS project_name
			FROM
				staffing s
				LEFT JOIN projects p ON s.project = p.id
			WHERE
				s.date BETWEEN DATE_TRUNC('week',
					start_date::date)
				AND(DATE_TRUNC('week',
						end_date::date) + INTERVAL '6 days')
			UNION ALL
			SELECT
				a.employee_id AS id,
				a.reason AS name,
				a.date AS joined_date,
				100 AS percentage,
				p.billable AS billable,
				p.name AS project_name
			FROM
				absence a
			LEFT JOIN projects p ON a.reason = p.id
			WHERE
				a.date BETWEEN DATE_TRUNC('week',
					start_date::date)
				AND(DATE_TRUNC('week',
						end_date::date) + INTERVAL '6 days')),
    			employee_data AS (
    				SELECT
    					id,
    					name,
    					project_name,
    					TO_CHAR(DATE_TRUNC('week',
    							joined_date),
    						'IYYY-IW') AS week,
                        DATE_TRUNC('week', joined_date)::date AS week_start,
    					jsonb_object_agg(joined_date,
    						percentage
    					ORDER BY
    						joined_date) AS days_in_week,
    					billable
    				FROM
    					joined_data
    				GROUP BY
    					id,
    					name,
    					project_name,
    					DATE_TRUNC('week',
    						joined_date),
    					billable),
				employee_weeks AS (
				    SELECT
						ed.id,
						ed.name,
						ed.project_name,
						ed.week,
						jsonb_build_object(
						    'dates', ed.days_in_week,
							'availability', availability_percentage(ed.week_start, (ed.week_start + INTERVAL '6 days')::date, ed.id)
						) AS week_data,
						ed.billable
					FROM
					    employee_data ed
				),
				employee_projects AS (
					SELECT
						id,
						name,
						project_name,
						jsonb_object_agg(week,
							week_data) AS week_data,
						billable
					FROM
						employee_weeks
					GROUP BY
						id,
						name,
						project_name,
						billable
)
				SELECT
					id,
					jsonb_agg(jsonb_build_object ('name',
							name,
							'billable',
							billable,
							'project_name',
							project_name) || week_data) AS subrows
				FROM
					employee_projects
				GROUP BY
					id
) s ON e.employee_id = s.id;
	RETURN result;
END;
$function$
