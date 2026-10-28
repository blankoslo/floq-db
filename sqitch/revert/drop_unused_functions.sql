-- Revert floq:drop_unused_functions from pg

-- Nothing to undo in sqitch: the functions come back by running functions/deploy.sh
-- from a commit before this change.
SELECT 1;
