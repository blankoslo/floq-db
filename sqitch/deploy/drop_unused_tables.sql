-- Deploy floq:drop_unused_tables to pg
-- requires: add_talks_table
-- requires: project_sdg
-- requires: ranked_tables
-- requires: add_trak

BEGIN;

-- talks was floq-kpi's, project_sdg_events floq-projects' (replaced by
-- projects-v2), the ranked tables floq-rank's and profession_task and
-- employee_task_comments the first Trak's; nothing else reads or writes them.
-- trak_v3 still uses the other add_trak tables.
DROP TABLE talks;
DROP TABLE project_sdg_events;
DROP TABLE ranked_matchups;
DROP TABLE ranked_games;
DROP TYPE ranked_matchup_result;
DROP TABLE profession_task;
DROP TABLE employee_task_comments;

COMMIT;
