#!/usr/bin/env bash
#
# scripts/explain.sh -- run db/queries/analytics.sql and show the query plan
# with and without the reporting index. See README.md, "Part 5".

# shellcheck source=scripts/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

wait_for_db
db_run psql -v ON_ERROR_STOP=1 --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
    -f /db/queries/analytics.sql
