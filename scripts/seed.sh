#!/usr/bin/env bash
#
# scripts/seed.sh -- (re)apply migrations and seed data to a running database.
#
# docker compose already runs these on first boot via
# /docker-entrypoint-initdb.d. This script exists for the second time onwards:
# after poking at the data you can get back to a known state without having to
# `docker compose down -v` and wait for a fresh initdb.
#
#   ./scripts/seed.sh                 # reset the default database
#   ./scripts/seed.sh -d bookings_x   # or some other one

# shellcheck source=scripts/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET_DB="$POSTGRES_DB"
while getopts ':d:h' opt; do
    case "$opt" in
        d) TARGET_DB="$OPTARG" ;;
        h) echo "usage: scripts/seed.sh [-d DB_NAME]" >&2; exit 0 ;;
        :) die "option -$OPTARG needs a value" ;;
        \?) die "unknown option -$OPTARG" ;;
    esac
done

wait_for_db

# Order matters, and all three files are written to be re-runnable:
# CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS / TRUNCATE + INSERT.
for file in \
    "$REPO_ROOT/db/migrations/0001_schema.sql" \
    "$REPO_ROOT/db/migrations/0002_indexes.sql" \
    "$REPO_ROOT/db/seed/0003_seed.sql"     "$REPO_ROOT/db/migrations/0004_pg_stat_statements.sql"
do
    log "applying $(basename "$file") -> $TARGET_DB"
    db_run psql -v ON_ERROR_STOP=1 --username="$POSTGRES_USER" --dbname="$TARGET_DB" --quiet -f - < "$file"
done

ok "'$TARGET_DB' reset to the seeded baseline"
