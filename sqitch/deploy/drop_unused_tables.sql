-- Deploy floq:drop_unused_tables to pg
-- requires: add_talks_table
-- requires: project_sdg
-- requires: ranked_tables

BEGIN;

-- talks was floq-kpi's, project_sdg_events floq-projects' (replaced by
-- projects-v2) and the ranked tables floq-rank's; nothing else reads or writes them.
DROP TABLE talks;
DROP TABLE project_sdg_events;
DROP TABLE ranked_matchups;
DROP TABLE ranked_games;
DROP TYPE ranked_matchup_result;

COMMIT;
