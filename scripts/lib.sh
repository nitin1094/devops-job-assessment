#!/usr/bin/env bash
# Shared helpers for the database scripts. Sourced, not executed.
#
# Everything talks to Postgres *through the compose container* rather than
# through a local psql, so the only host dependency is Docker itself.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# .env is optional -- the defaults below match docker-compose.yml.
if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$REPO_ROOT/.env"
    set +a
fi

POSTGRES_USER="${POSTGRES_USER:-bookings}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-bookings_local_pw}"
POSTGRES_DB="${POSTGRES_DB:-bookings}"
DB_SERVICE="${DB_SERVICE:-db}"
BACKUP_DIR="${BACKUP_DIR:-$REPO_ROOT/backups}"
BACKUP_RETENTION="${BACKUP_RETENTION:-7}"
# How many times wait_for_db polls before giving up; each attempt sleeps 2s.
DB_WAIT_RETRIES="${DB_WAIT_RETRIES:-60}"

if [ -t 2 ]; then
    C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_OFF=$'\033[0m'
else
    C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_OFF=''
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE"   "$C_OFF" "$*" >&2; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN"  "$C_OFF" "$*" >&2; }
warn() { printf '%s  !!%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$C_RED"   "$C_OFF" "$*" >&2; exit 1; }

# --- docker compose plumbing -------------------------------------------------

if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD=""
fi

compose() {
    [ -n "$COMPOSE_CMD" ] || die "docker compose not found on PATH -- install Docker Desktop or the compose plugin"
    # COMPOSE_CMD holds either "docker compose" or "docker-compose", so the
    # word splitting below is deliberate.
    # shellcheck disable=SC2086
    ( cd "$REPO_ROOT" && $COMPOSE_CMD "$@" )
}

# Run a binary inside the db container. stdin/stdout are passed straight
# through, which is what lets pg_dump stream to a file on the host.
db_run() {
    compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_SERVICE" "$@"
}

# Run SQL and return the raw result (no headers, no padding).
db_query() {
    local dbname="$1"; shift
    db_run psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$dbname" -At -F '|' -c "$*" | tr -d '\r'
}

wait_for_db() {
    local i

    compose ps --status running "$DB_SERVICE" >/dev/null 2>&1 || true
    if [ -z "$(compose ps -q "$DB_SERVICE" 2>/dev/null)" ]; then
        die "the '$DB_SERVICE' service is not running -- start it with: docker compose up -d"
    fi

    log "waiting for postgres to accept TCP connections"
    for ((i = 1; i <= DB_WAIT_RETRIES; i++)); do
        # -h 127.0.0.1 on purpose: during first boot the entrypoint runs the
        # migration/seed files against a temporary server that listens on the
        # unix socket only. A socket pg_isready would report "ready" while the
        # seed is still running and every script downstream would race it.
        if db_run pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q >/dev/null 2>&1; then
            ok "postgres is ready"
            return 0
        fi
        sleep 2
    done
    die "postgres was not ready after $((DB_WAIT_RETRIES * 2))s"
}

# A cheap content fingerprint, used to prove a restore actually round-tripped.
# Emits: <bookings>|<events>|<sum_amount>|<md5 of all booking ids in order>
db_fingerprint() {
    local dbname="$1"
    db_query "$dbname" "
        SELECT (SELECT count(*) FROM hotel_bookings),
               (SELECT count(*) FROM booking_events),
               (SELECT coalesce(sum(amount), 0) FROM hotel_bookings),
               (SELECT coalesce(md5(string_agg(id::text, ',' ORDER BY id)), 'empty') FROM hotel_bookings);
    "
}
