#!/usr/bin/env bash
#
# scripts/psql.sh -- interactive psql inside the db container, no local client
# needed. Any arguments are passed straight through:
#
#   ./scripts/psql.sh
#   ./scripts/psql.sh -d bookings_restore_20260918120000
#   ./scripts/psql.sh -c 'SELECT count(*) FROM hotel_bookings'
#
# The repo's db/ directory is mounted read-only at /db in the container, so:
#   ./scripts/psql.sh -f /db/queries/analytics.sql

# shellcheck source=scripts/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# docker compose exec allocates a TTY by default and fails outright when there
# is not one, which is exactly the situation in CI. Detect it rather than always
# passing -T, so the interactive case still gets a usable psql prompt.
tty_flag=()
if [ ! -t 0 ] || [ ! -t 1 ]; then
    tty_flag=(-T)
fi

# A later -d on the command line overrides this one, which is exactly what we
# want for the "-d some_other_db" case above.
compose exec "${tty_flag[@]}" -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_SERVICE" \
    psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" "$@"
