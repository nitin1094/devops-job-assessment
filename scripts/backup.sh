#!/usr/bin/env bash
#
# scripts/backup.sh -- take a timestamped dump of the local bookings database.
#
#   ./scripts/backup.sh                 # dump into ./backups
#   ./scripts/backup.sh -o /tmp/dumps   # somewhere else
#
# Output is pg_dump's custom format (-Fc): compressed, and restorable
# selectively with pg_restore, which plain SQL dumps cannot do.
#
# Alongside each dump we write a .meta sidecar holding a content fingerprint
# taken at dump time. scripts/restore.sh compares the restored database against
# that fingerprint, so "the restore worked" is an assertion and not a vibe.

# shellcheck source=scripts/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
    cat >&2 <<'USAGE'
usage: scripts/backup.sh [-o OUTPUT_DIR] [-k KEEP] [-h]

  -o OUTPUT_DIR   where to write the dump      (default: ./backups)
  -k KEEP         how many dumps to keep       (default: $BACKUP_RETENTION, 7)
  -h              show this help
USAGE
}

while getopts ':o:k:h' opt; do
    case "$opt" in
        o) BACKUP_DIR="$OPTARG" ;;
        k) BACKUP_RETENTION="$OPTARG" ;;
        h) usage; exit 0 ;;
        :) die "option -$OPTARG needs a value" ;;
        \?) usage; die "unknown option -$OPTARG" ;;
    esac
done

checksum_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "unavailable"
    fi
}

prune_old_dumps() {
    local keep="$1" old count
    count="$(find "$BACKUP_DIR" -maxdepth 1 -name "${POSTGRES_DB}-*.dump" | wc -l | tr -d ' ')"
    [ "$count" -gt "$keep" ] || return 0

    # Filenames carry a UTC timestamp in basic ISO-8601 form, so a plain
    # lexicographic sort is also a chronological sort.
    find "$BACKUP_DIR" -maxdepth 1 -name "${POSTGRES_DB}-*.dump" | sort | head -n "$((count - keep))" |
        while IFS= read -r old; do
            rm -f "$old" "$old.meta"
            warn "pruned $(basename "$old")"
        done
}

main() {
    wait_for_db

    mkdir -p "$BACKUP_DIR"

    local stamp dump tmp fingerprint pg_version
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    dump="$BACKUP_DIR/${POSTGRES_DB}-${stamp}.dump"
    tmp="$dump.partial"

    # A half-written dump is worse than no dump -- never leave one behind.
    trap 'rm -f "$tmp"' EXIT INT TERM

    log "dumping database '$POSTGRES_DB'"
    db_run pg_dump \
        --username="$POSTGRES_USER" \
        --dbname="$POSTGRES_DB" \
        --format=custom \
        --no-owner \
        --no-privileges > "$tmp"

    [ -s "$tmp" ] || die "pg_dump produced an empty file"
    mv "$tmp" "$dump"
    trap - EXIT INT TERM

    fingerprint="$(db_fingerprint "$POSTGRES_DB")"
    pg_version="$(db_query "$POSTGRES_DB" 'SHOW server_version;')"

    {
        echo "database=$POSTGRES_DB"
        echo "created_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "server_version=$pg_version"
        echo "dump_format=custom"
        echo "hotel_bookings_rows=$(echo "$fingerprint" | cut -d'|' -f1)"
        echo "booking_events_rows=$(echo "$fingerprint" | cut -d'|' -f2)"
        echo "sum_amount=$(echo "$fingerprint" | cut -d'|' -f3)"
        echo "booking_id_md5=$(echo "$fingerprint" | cut -d'|' -f4)"
        echo "sha256=$(checksum_of "$dump")"
    } > "$dump.meta"

    ok "wrote $(basename "$dump") ($(du -h "$dump" | cut -f1))"
    ok "wrote $(basename "$dump").meta"

    prune_old_dumps "$BACKUP_RETENTION"

    log "backups currently on disk:"
    ls -1sh "$BACKUP_DIR"/*.dump >&2
}

main "$@"
