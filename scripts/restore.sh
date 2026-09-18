#!/usr/bin/env bash
#
# scripts/restore.sh -- restore a dump into a *fresh* database and verify it.
#
#   ./scripts/restore.sh                            # newest dump -> new db
#   ./scripts/restore.sh backups/bookings-2026....dump
#   ./scripts/restore.sh --into bookings_check
#   ./scripts/restore.sh --replace                  # overwrite the live local db
#   ./scripts/restore.sh --replace --yes            # ...without the confirmation
#
# By default nothing existing is touched: the dump goes into a brand new
# database called <db>_restore_<timestamp>, which is then compared against the
# fingerprint captured in the .meta sidecar at backup time. The script exits
# non-zero if they disagree, so it is safe to use in CI.

# shellcheck source=scripts/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DUMP_FILE=""
TARGET_DB=""
REPLACE=0
ASSUME_YES=0

usage() {
    cat >&2 <<'USAGE'
usage: scripts/restore.sh [DUMP_FILE] [--into DB_NAME] [--replace] [-h]

  DUMP_FILE       dump to restore            (default: newest in ./backups)
  --into DB_NAME  restore into this database (default: <db>_restore_<stamp>)
  --replace       drop and recreate the live local database instead
  -y, --yes       skip the confirmation prompt (for CI)
  -h, --help      show this help
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --into)    TARGET_DB="${2:-}"; [ -n "$TARGET_DB" ] || die "--into needs a database name"; shift 2 ;;
        --replace) REPLACE=1; shift ;;
        -y|--yes)  ASSUME_YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*)        usage; die "unknown option $1" ;;
        *)         DUMP_FILE="$1"; shift ;;
    esac
done

newest_dump() {
    find "$BACKUP_DIR" -maxdepth 1 -name '*.dump' 2>/dev/null | sort | tail -n 1
}

meta_value() {
    # meta_value <file> <key>
    [ -f "$1" ] || return 0
    sed -n "s/^$2=//p" "$1" | tr -d '\r'
}

main() {
    [ -n "$DUMP_FILE" ] || DUMP_FILE="$(newest_dump)"
    [ -n "$DUMP_FILE" ] || die "no dump found in $BACKUP_DIR -- run ./scripts/backup.sh first"
    [ -f "$DUMP_FILE" ] || die "no such file: $DUMP_FILE"

    local meta="$DUMP_FILE.meta"

    if [ "$REPLACE" -eq 1 ]; then
        [ -z "$TARGET_DB" ] || die "--into and --replace are mutually exclusive"
        TARGET_DB="$POSTGRES_DB"
    elif [ -z "$TARGET_DB" ]; then
        TARGET_DB="${POSTGRES_DB}_restore_$(date -u +%Y%m%d%H%M%S)"
    fi

    wait_for_db

    if [ -f "$meta" ]; then
        log "dump taken $(meta_value "$meta" created_at_utc) from '$(meta_value "$meta" database)' (postgres $(meta_value "$meta" server_version))"
    else
        warn "no .meta sidecar next to this dump -- restoring, but verification will be skipped"
    fi

    if [ "$REPLACE" -eq 1 ] && [ "$ASSUME_YES" -eq 0 ]; then
        warn "--replace will DROP the live database '$TARGET_DB'"
        printf 'type the database name to confirm: ' >&2
        read -r confirm
        [ "$confirm" = "$TARGET_DB" ] || die "aborted"
    fi

    log "creating database '$TARGET_DB'"
    # --force terminates any leftover sessions; without it a stray psql shell is
    # enough to make DROP DATABASE fail.
    db_run dropdb --username="$POSTGRES_USER" --if-exists --force "$TARGET_DB"
    db_run createdb --username="$POSTGRES_USER" "$TARGET_DB"

    log "restoring $(basename "$DUMP_FILE") into '$TARGET_DB'"
    # --single-transaction makes the restore atomic: any error and the new
    # database is left empty rather than half-populated.
    db_run pg_restore \
        --username="$POSTGRES_USER" \
        --dbname="$TARGET_DB" \
        --no-owner \
        --no-privileges \
        --single-transaction < "$DUMP_FILE"

    ok "restore finished"

    # --- verification --------------------------------------------------------

    local restored bookings events amount md5sum
    restored="$(db_fingerprint "$TARGET_DB")"
    bookings="$(echo "$restored" | cut -d'|' -f1)"
    events="$(echo   "$restored" | cut -d'|' -f2)"
    amount="$(echo   "$restored" | cut -d'|' -f3)"
    md5sum="$(echo   "$restored" | cut -d'|' -f4)"

    if [ ! -f "$meta" ]; then
        log "restored contents:"
        printf '  hotel_bookings rows : %s\n  booking_events rows : %s\n  sum(amount)         : %s\n' \
            "$bookings" "$events" "$amount" >&2
        ok "database '$TARGET_DB' is ready (not verified -- no .meta file)"
        return 0
    fi

    local failures=0
    check() {
        # check <label> <expected> <actual>
        if [ "$2" = "$3" ]; then
            printf '  %-22s %-38s %sPASS%s\n' "$1" "$3" "$C_GREEN" "$C_OFF" >&2
        else
            printf '  %-22s %-38s %sFAIL%s (expected %s)\n' "$1" "$3" "$C_RED" "$C_OFF" "$2" >&2
            failures=$((failures + 1))
        fi
    }

    log "verifying '$TARGET_DB' against the fingerprint taken at backup time"
    printf '  %-22s %-38s %s\n' "check" "restored value" "result" >&2
    check "hotel_bookings rows" "$(meta_value "$meta" hotel_bookings_rows)" "$bookings"
    check "booking_events rows" "$(meta_value "$meta" booking_events_rows)" "$events"
    check "sum(amount)"         "$(meta_value "$meta" sum_amount)"          "$amount"
    check "booking id md5"      "$(meta_value "$meta" booking_id_md5)"      "$md5sum"

    if [ "$failures" -ne 0 ]; then
        die "$failures check(s) failed -- the restore did not round-trip"
    fi

    ok "all checks passed -- '$TARGET_DB' matches the backup exactly"
    log "inspect it with: ./scripts/psql.sh -d $TARGET_DB"
}

main "$@"
