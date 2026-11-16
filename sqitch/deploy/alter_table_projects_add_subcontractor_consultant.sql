-- Deploy floq:alter_table_projects_add_subcontractor_consultant to pg
-- requires: alter_table_projects_add_subcontractor_flag

BEGIN;

-- Not NOT NULL when flagged: projects already flagged before these columns existed have none of them.
-- The platform requires all three on any write that sets the flag.
ALTER TABLE projects
  ADD COLUMN subcontractor_consultant_name text,
  ADD COLUMN subcontractor_hourly_rate     numeric(10,2)
    CONSTRAINT projects_subcontractor_hourly_rate_not_negative CHECK (subcontractor_hourly_rate >= 0),
  ADD COLUMN subcontractor_margin          numeric(5,2)
    CONSTRAINT projects_subcontractor_margin_is_percentage CHECK (subcontractor_margin BETWEEN 0 AND 100),
  ADD CONSTRAINT projects_subcontractor_consultant_only_when_flagged CHECK (
    has_subcontractor_consultants
    OR (subcontractor_consultant_name IS NULL
        AND subcontractor_hourly_rate IS NULL
        AND subcontractor_margin IS NULL)
  );

COMMIT;
