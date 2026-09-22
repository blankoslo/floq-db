-- Deploy floq:add_sales_case_archived to pg
-- requires: add_sales_pipeline

BEGIN;

-- Trello's archive is not a column floq had. A card was archived out of whichever
-- list it stood in, so being archived says nothing about the stage, and the stage
-- says nothing about being archived: about 240 cards that died in Identifisert
-- during 2025 came over as live work because the import had no way to say so.
--
-- The hide rule cannot do this job. It measures stage_since, and a live card
-- nobody has touched for six months is still live.
ALTER TABLE sales_case ADD COLUMN archived_at TIMESTAMPTZ;

-- The board reads the open cards, and every hidden one is dead weight in the
-- index once the Trello history is in.
DROP INDEX sales_case_board_idx;
CREATE INDEX sales_case_board_idx ON sales_case (stage_slug, stage_since DESC)
    WHERE archived_at IS NULL;

COMMIT;
