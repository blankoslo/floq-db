CREATE OR REPLACE FUNCTION public.weekly_fg_json(start_date date, end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
	cur_week_start date;
	period_end date;
	result jsonb := '{}'::jsonb;
	str_week text;
	ffg_value double precision;
BEGIN
	cur_week_start := DATE_TRUNC('week', start_date);
	period_end := DATE_TRUNC('week', end_date);
	WHILE cur_week_start <= period_end LOOP
		str_week := TO_CHAR(cur_week_start, 'IYYY-IW');
		SELECT
			ffg.percent INTO ffg_value
		FROM
			forcasted_fg_in_period (cur_week_start,
				(cur_week_start + INTERVAL '6 days')::date) ffg;
		result := result || jsonb_build_object (str_week,
			TRUNC(ffg_value));
		cur_week_start := cur_week_start::date + INTERVAL '7 days';
	END LOOP;
	RETURN result;
END
$function$
