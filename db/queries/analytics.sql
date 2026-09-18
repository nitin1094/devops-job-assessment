-- analytics.sql
-- The query from the brief, plus a self-contained before/after comparison.
--
-- Run it with:
--   docker compose exec -T db psql -U bookings -d bookings -f - < db/queries/analytics.sql
-- or:
--   ./scripts/psql.sh -f /work/db/queries/analytics.sql
--
-- The "before" plan is produced by dropping the index inside a transaction and
-- rolling back, so nothing is actually lost -- no need to re-seed to compare.

\timing on

\echo '== the query =='
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;

\echo ''
\echo '== BEFORE: plan without hotel_bookings_city_created_at_idx =='
BEGIN;
DROP INDEX hotel_bookings_city_created_at_idx;
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
ROLLBACK;

\echo ''
\echo '== AFTER: plan with the index =='
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;

\echo ''
\echo '== index sizes =='
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size,
       idx_scan AS times_used
FROM pg_stat_user_indexes
WHERE relname IN ('hotel_bookings', 'booking_events')
ORDER BY relname, indexrelname;
