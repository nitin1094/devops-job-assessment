-- slow_queries.sql
-- Top statements by total execution time. This is the first thing to run when
-- something is slow and nobody knows what.
--
--   ./scripts/psql.sh -f /db/queries/slow_queries.sql
--
-- Reset the counters between experiments with:
--   SELECT pg_stat_statements_reset();

SELECT
    calls,
    round(total_exec_time::numeric, 1)       AS total_ms,
    round(mean_exec_time::numeric, 2)        AS mean_ms,
    rows,
    -- Ratio of rows returned to blocks read: a low number on a big table is the
    -- signature of a missing index.
    shared_blks_read                         AS blocks_read_from_disk,
    shared_blks_hit                          AS blocks_from_cache,
    left(regexp_replace(query, '\s+', ' ', 'g'), 120) AS query
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 20;
