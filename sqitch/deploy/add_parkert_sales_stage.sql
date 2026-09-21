-- Deploy floq:add_parkert_sales_stage to pg
-- requires: add_sales_pipeline

BEGIN;

-- Trello has a «Parkert» list and floq did not. It was empty when the board was
-- surveyed and had 39 cards in it when the export was taken, so the import has
-- somewhere to put work that is on hold rather than lost.
--
-- Not terminal: a parked case can come back, and the column is not one of the
-- three the board reads as an outcome. It still hides after six months, because
-- the hide rule measures hides_after_months alone — a case nobody has touched
-- since spring is history whether it was won or shelved.
INSERT INTO sales_stage (slug, label, sort_order, is_terminal, hides_after_months) VALUES
    ('parkert', 'Parkert', 45, FALSE, 6);

COMMIT;
