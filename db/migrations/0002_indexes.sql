-- 0002_indexes.sql
-- Indexes that support the reporting query in db/queries/analytics.sql.
-- Rationale is written up in README.md ("Part 5 - the index and why").
--
-- On a live RDS instance these would be created with CREATE INDEX CONCURRENTLY
-- (outside a transaction) so the write path is not blocked. The local bootstrap
-- runs against an empty table, so a plain CREATE INDEX is fine here.

BEGIN;

-- Supports:
--   WHERE city = ? AND created_at >= ?  GROUP BY org_id, status
--
-- (city, created_at) -> equality column first, range column second, so the
-- range scan stays contiguous in the B-tree.
-- INCLUDE (org_id, status, amount) -> the three columns the aggregate needs are
-- carried in the leaf pages, which lets the planner use an index-only scan and
-- never touch the heap.
CREATE INDEX IF NOT EXISTS hotel_bookings_city_created_at_idx
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);

-- Every FK deserves an index on the child side: without it, deleting a booking
-- forces a sequential scan of booking_events, and "events for this booking"
-- (the common read) does the same.
CREATE INDEX IF NOT EXISTS booking_events_booking_id_created_at_idx
    ON booking_events (booking_id, created_at);

COMMIT;
