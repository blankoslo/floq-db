-- Deploy floq:absence_table to pg

BEGIN;

-- is_holiday/is_absence_reason live here rather than functions/ because these
-- CHECK constraints need them to exist before this table can be created; a
-- clean deploy can't rely on functions/ having run first.
CREATE OR REPLACE FUNCTION is_holiday(d date)
        RETURNS boolean AS
$$
BEGIN
  RETURN EXISTS (SELECT * FROM public.holidays WHERE holidays.date = d);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION is_absence_reason(reason text)
        RETURNS boolean AS
$$
BEGIN
  RETURN (    reason = 'FER1000'
           OR reason = 'SYK1000'
           OR reason = 'SYK1001'
           OR reason = 'SYK1002'
           OR reason = 'PER1000'
           OR reason = 'PER1001'
           OR reason = 'PER1002'
           OR reason = 'FAG1000'
           OR reason = 'AVS'
         );
END
$$ LANGUAGE plpgsql;

-- absence_reasons lives here too (not just in functions/) since absence_spent,
-- add_view_available_projects, and remove_absence_from_staffing all query it
-- directly — keeping it a single real view, matching how it behaves on
-- already-deployed environments, rather than duplicating its filter logic
-- across every consumer.
CREATE OR REPLACE VIEW absence_reasons
         AS ( SELECT id, name, billable FROM projects WHERE is_absence_reason(id)
              UNION ALL
              SELECT 'AVS' as id, 'Avspasering' as name, 'nonbillable' as billable
            );

CREATE TABLE absence (
  employee_id integer NOT NULL REFERENCES employees(id),

  date date NOT NULL,
    CHECK(NOT is_holiday(date)),

  reason text NOT NULL REFERENCES projects(id),
    CHECK(is_absence_reason(reason)),

  PRIMARY KEY (employee_id, date)
);

INSERT INTO absence (employee_id, date, reason)
  ( SELECT employee, date, project as reason
      FROM staffing
     WHERE is_absence_reason(project) AND NOT is_holiday(date)
  );

DELETE FROM staffing WHERE is_absence_reason(project);

COMMIT;
