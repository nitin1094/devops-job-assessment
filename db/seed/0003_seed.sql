-- 0003_seed.sql
-- Deterministic seed data (setseed makes every run produce the same rows, so
-- EXPLAIN output is comparable between machines).
--
-- The brief asks for "at least 100" bookings. 100 rows is not enough to make the
-- planner do anything interesting -- at that size a sequential scan is genuinely
-- the cheapest plan and the index in 0002 would never be used. I seed 20,000
-- bookings so the before/after in db/queries/analytics.sql is a real result and
-- not a staged one.

BEGIN;

SELECT setseed(0.42);

TRUNCATE booking_events, hotel_bookings RESTART IDENTITY CASCADE;

-- Repeated entries in these arrays are the weighting: delhi shows up 3x out of
-- 13 slots, "confirmed" 4x out of 9, etc. Crude, but it keeps the seed to one
-- statement and gives a skewed distribution like real data has.
WITH ref AS (
    SELECT
        ARRAY['delhi', 'delhi', 'delhi', 'mumbai', 'mumbai', 'bengaluru', 'bengaluru',
              'hyderabad', 'pune', 'chennai', 'kolkata', 'jaipur', 'goa']::text[] AS cities,
        ARRAY['confirmed', 'confirmed', 'confirmed', 'confirmed', 'completed', 'completed',
              'pending', 'cancelled', 'refunded']::text[] AS statuses
),
base AS (
    SELECT
        gs.i,
        -- 8 stable tenant UUIDs, so org_id is readable while eyeballing results
        ('00000000-0000-0000-0000-' || lpad(((floor(random() * 8))::int + 1)::text, 12, '0'))::uuid AS org_id,
        (floor(random() * 450))::int + 1                                              AS hotel_no,
        ref.cities[(floor(random() * array_length(ref.cities, 1)))::int + 1]          AS city,
        ref.statuses[(floor(random() * array_length(ref.statuses, 1)))::int + 1]      AS status,
        round((1500 + random() * 48500)::numeric, 2)                                  AS amount,
        -- spread over 180 days so the "last 30 days" filter is actually selective
        (now() - (random() * INTERVAL '180 days'))::timestamp                         AS created_at,
        (floor(random() * 43))::int + 3                                               AS lead_days,
        (floor(random() * 7))::int + 1                                                AS nights
    FROM generate_series(1, 20000) AS gs(i)
    CROSS JOIN ref
)
INSERT INTO hotel_bookings (id, org_id, hotel_id, city, checkin_date, checkout_date, amount, status, created_at)
SELECT
    -- derived from the row number rather than gen_random_uuid() so the whole
    -- seed -- ids included -- is byte-for-byte reproducible
    md5('booking:' || base.i)::uuid,
    base.org_id,
    'HTL-' || lpad(base.hotel_no::text, 4, '0'),
    base.city,
    (base.created_at + (base.lead_days * INTERVAL '1 day'))::date,
    (base.created_at + ((base.lead_days + base.nights) * INTERVAL '1 day'))::date,
    base.amount,
    base.status,
    base.created_at
FROM base;

-- Roughly 40% of bookings get an event trail, 1-3 events each.
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    s.id,
    (ARRAY['booking_created', 'payment_authorized', 'booking_confirmed'])[g.ord],
    jsonb_build_object(
        'source',   'booking-api',
        'channel',  s.channel,
        'amount',   s.amount,
        'currency', 'INR',
        'sequence', g.ord
    ),
    s.created_at + (g.ord * INTERVAL '4 minutes')
FROM (
    SELECT
        id,
        amount,
        created_at,
        (ARRAY['web', 'ios', 'android', 'partner-api'])[(floor(random() * 4))::int + 1] AS channel,
        (floor(random() * 3))::int + 1                                                  AS event_count
    FROM hotel_bookings
    WHERE random() < 0.4
) AS s
CROSS JOIN LATERAL generate_series(1, s.event_count) AS g(ord);

COMMIT;

-- Stats matter more than the rows: without an ANALYZE the planner has no idea
-- how selective city = 'delhi' is and may ignore the index entirely.
VACUUM (ANALYZE) hotel_bookings;
VACUUM (ANALYZE) booking_events;

SELECT 'hotel_bookings' AS table_name, count(*) AS rows FROM hotel_bookings
UNION ALL
SELECT 'booking_events', count(*) FROM booking_events;

SELECT city, count(*) AS bookings
FROM hotel_bookings
GROUP BY city
ORDER BY bookings DESC;
