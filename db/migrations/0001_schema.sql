-- 0001_schema.sql
-- Core booking tables.
--
-- Note on types: the assignment specifies TIMESTAMP (without time zone) and I have
-- kept it as-is so the schema matches the brief. In a real multi-region booking
-- system I would use TIMESTAMPTZ for created_at -- see README "Schema notes".

BEGIN;

CREATE TABLE IF NOT EXISTS hotel_bookings (
    id            UUID           PRIMARY KEY,
    org_id        UUID           NOT NULL,
    hotel_id      VARCHAR(100)   NOT NULL,
    city          VARCHAR(100)   NOT NULL,
    checkin_date  DATE           NOT NULL,
    checkout_date DATE           NOT NULL,
    amount        NUMERIC(12, 2) NOT NULL,
    status        VARCHAR(50)    NOT NULL,
    created_at    TIMESTAMP      NOT NULL DEFAULT now(),

    CONSTRAINT hotel_bookings_dates_chk  CHECK (checkout_date > checkin_date),
    CONSTRAINT hotel_bookings_amount_chk CHECK (amount >= 0)
);

CREATE TABLE IF NOT EXISTS booking_events (
    id         BIGSERIAL    PRIMARY KEY,
    booking_id UUID         NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload    JSONB,
    created_at TIMESTAMP    NOT NULL DEFAULT now(),

    CONSTRAINT booking_events_booking_fk
        FOREIGN KEY (booking_id) REFERENCES hotel_bookings (id) ON DELETE CASCADE
);

COMMENT ON TABLE hotel_bookings IS 'One row per hotel booking, owned by an organisation (tenant).';
COMMENT ON TABLE booking_events IS 'Append-only event log for a booking (state changes, payments, webhooks).';

COMMIT;
