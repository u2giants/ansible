#!/usr/bin/env bash
# test-restore.sh — prove that the backups actually restore.
#
# Until this script existed, nothing had ever demonstrated that a snapshot in the
# DigitalOcean Spaces restic repository could be turned back into a working database.
# The backups were *unproven*: Backrest reported success, the Restore Wizard showed green,
# and nobody had ever pulled one back and looked at it.
#
# What it does, end to end:
#   1. restores the newest `coolify-db-latest.sql` from the OFFSITE restic repo
#      (not the local copy on this box — restoring the local file would prove nothing)
#   2. starts a throwaway PostgreSQL container on a private network
#   3. loads the dump into it
#   4. sanity-checks the result: expected tables exist and hold plausible row counts
#   5. tears everything down
#   6. writes a machine-readable verdict to $RESULT_FILE for the Restore Wizard to display
#
# It is READ-ONLY with respect to production: it reads from the restic repo, and every
# container, volume, and file it creates is its own and is removed on exit. It never
# touches `coolify-db`, the live volumes, or the restic repo's contents.
#
# Usage:  sudo /opt/backrest/scripts/test-restore.sh [--keep]
#         --keep leaves the restored dump and the temp container up for inspection.
#
# Exit codes: 0 = restore verified, 1 = restore FAILED (the thing we actually want to know),
#             2 = the test itself could not run (missing creds, no docker, etc.)

set -euo pipefail

BACKREST_DIR="${BACKREST_DIR:-/opt/backrest}"
ENV_FILE="$BACKREST_DIR/.env"
RESULT_DIR="${RESULT_DIR:-$BACKREST_DIR/restore-tests}"
RESULT_FILE="$RESULT_DIR/latest.json"
LOG_FILE="$RESULT_DIR/latest.log"

REPO_URI="${REPO_URI:-s3:https://nyc3.digitaloceanspaces.com/backrest}"
RESTIC_IMAGE="${RESTIC_IMAGE:-restic/restic:0.18.1}"
# Must match the live Coolify database's major version (15.x as of 2026-08-23) — a dump from
# a newer server will not load into an older one.
PG_IMAGE="${PG_IMAGE:-postgres:15-alpine}"

# The file we pull back. It lives in the `db-dumps` plan's snapshots.
DUMP_NAME="coolify-db-latest.sql"
DUMP_PATH="/db-dumps/$DUMP_NAME"
SNAPSHOT_TAG="${SNAPSHOT_TAG:-plan:db-dumps}"

# Tables that must exist with at least this many rows for the restore to count as verified.
# Chosen because Coolify cannot function without them; if these are empty the dump loaded
# but is useless, which is a FAILURE, not a pass.
declare -A MIN_ROWS=(
  [users]=1
  [servers]=1
  [applications]=1
)

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

RUN_ID="restore-test-$$-$(date -u +%Y%m%d%H%M%S)"
PG_CONTAINER="$RUN_ID-pg"
PG_PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -d '/+=' )"
WORK_DIR=""
CRED_FILE=""
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_EPOCH="$(date +%s)"

mkdir -p "$RESULT_DIR"
chmod 700 "$RESULT_DIR"

log() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG_FILE" >&2; }

# ── result reporting ──────────────────────────────────────────────────────────
# Always leave a verdict behind, even on an unexpected crash. A missing result file is
# indistinguishable from "nobody ran the test", which is the state we are trying to leave.
STATUS="error"
DETAIL="the test did not reach a verdict"
SNAPSHOT_ID=""
SNAPSHOT_TIME=""
DUMP_BYTES=0
declare -A ROW_COUNTS=()

write_result() {
  local duration=$(( $(date +%s) - START_EPOCH ))
  local rows_json="{}"
  if ((${#ROW_COUNTS[@]})); then
    rows_json="{$(for t in "${!ROW_COUNTS[@]}"; do printf '"%s":%s,' "$t" "${ROW_COUNTS[$t]}"; done | sed 's/,$//')}"
  fi
  umask 077
  cat > "$RESULT_FILE" <<JSON
{
  "status": "$STATUS",
  "detail": "$DETAIL",
  "started_at": "$STARTED_AT",
  "finished_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "duration_seconds": $duration,
  "repo": "$REPO_URI",
  "snapshot_id": "$SNAPSHOT_ID",
  "snapshot_time": "$SNAPSHOT_TIME",
  "dump": "$DUMP_NAME",
  "dump_bytes": $DUMP_BYTES,
  "row_counts": $rows_json,
  "log": "$LOG_FILE"
}
JSON
  log "verdict: $STATUS — $DETAIL"
}

cleanup() {
  local rc=$?
  if (( KEEP == 0 )); then
    docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
  else
    log "--keep: left container $PG_CONTAINER and $WORK_DIR in place"
  fi
  # Credentials never linger, --keep or not.
  [[ -n "$CRED_FILE" && -f "$CRED_FILE" ]] && rm -f "$CRED_FILE"
  write_result
  exit $rc
}
trap cleanup EXIT

fail()  { STATUS="failed"; DETAIL="$1"; log "FAIL: $1"; exit 1; }
abort() { STATUS="error";  DETAIL="$1"; log "ERROR: $1"; exit 2; }

: > "$LOG_FILE"
log "=== restore test $RUN_ID ==="

# ── 0. preconditions ──────────────────────────────────────────────────────────
command -v docker >/dev/null || abort "docker is not installed"
[[ -r "$ENV_FILE" ]] || abort "cannot read $ENV_FILE"

# Credentials are written to a 0600 file and passed via --env-file, never as command
# arguments — argv is world-readable in /proc. The file is removed by cleanup().
umask 077
WORK_DIR="$(mktemp -d "${RESULT_DIR}/work.XXXXXX")"
CRED_FILE="$(mktemp "${RESULT_DIR}/cred.XXXXXX")"
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
: "${DO_SPACES_ACCESS_KEY:?missing in $ENV_FILE}"
: "${DO_SPACES_SECRET_KEY:?missing in $ENV_FILE}"
: "${RESTIC_PASSWORD:?missing in $ENV_FILE}"
{
  printf 'AWS_ACCESS_KEY_ID=%s\n' "$DO_SPACES_ACCESS_KEY"
  printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$DO_SPACES_SECRET_KEY"
  printf 'RESTIC_PASSWORD=%s\n' "$RESTIC_PASSWORD"
} > "$CRED_FILE"

restic_run() {
  docker run --rm --env-file "$CRED_FILE" \
    -v "$WORK_DIR:/restore" \
    "$RESTIC_IMAGE" -r "$REPO_URI" "$@"
}

# ── 1. find the newest db-dumps snapshot ──────────────────────────────────────
log "locating the newest '$SNAPSHOT_TAG' snapshot in $REPO_URI"
snap_json="$(restic_run snapshots --tag "$SNAPSHOT_TAG" --latest 1 --json 2>>"$LOG_FILE")" \
  || abort "could not list snapshots — repo unreachable or credentials rejected"
SNAPSHOT_ID="$(printf '%s' "$snap_json" | jq -r '.[0].short_id // empty')"
SNAPSHOT_TIME="$(printf '%s' "$snap_json" | jq -r '.[0].time // empty')"
[[ -n "$SNAPSHOT_ID" ]] || fail "no snapshot found with tag $SNAPSHOT_TAG — nothing to restore"
log "snapshot $SNAPSHOT_ID from $SNAPSHOT_TIME"

# ── 2. restore just the one dump ──────────────────────────────────────────────
# --include keeps this to ~87 MB instead of the whole 8 GB db-dumps directory.
log "restoring $DUMP_PATH"
restic_run restore "$SNAPSHOT_ID" --target /restore --include "$DUMP_PATH" >>"$LOG_FILE" 2>&1 \
  || fail "restic restore failed — the snapshot could not be read back"

restored="$WORK_DIR$DUMP_PATH"
[[ -s "$restored" ]] || fail "restored file is missing or empty at $DUMP_PATH"
DUMP_BYTES="$(stat -c %s "$restored")"
log "restored $DUMP_BYTES bytes"
(( DUMP_BYTES > 1048576 )) || fail "restored dump is only $DUMP_BYTES bytes — implausibly small"

head -c 200 "$restored" | grep -q 'PostgreSQL database cluster dump' \
  || fail "restored file does not look like a pg_dumpall cluster dump"

# ── 3. throwaway PostgreSQL ───────────────────────────────────────────────────
log "starting throwaway $PG_IMAGE as $PG_CONTAINER"
docker run -d --name "$PG_CONTAINER" \
  --network none \
  -e POSTGRES_PASSWORD="$PG_PASSWORD" \
  --tmpfs /var/lib/postgresql/data:rw,size=2g \
  "$PG_IMAGE" >>"$LOG_FILE" 2>&1 \
  || abort "could not start the throwaway postgres container"

for i in $(seq 1 60); do
  if docker exec "$PG_CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  (( i == 60 )) && abort "throwaway postgres never became ready"
  sleep 2
done
log "postgres ready"

# ── 4. load the dump ──────────────────────────────────────────────────────────
# pg_dumpall output is a cluster dump: it creates the roles and databases itself.
# ON_ERROR_STOP is deliberately NOT set — a cluster dump always emits some benign
# "role already exists" noise. We judge by the sanity checks below, not by stderr.
log "loading the dump"
if ! docker exec -i "$PG_CONTAINER" psql -U postgres -q -f - < "$restored" \
      >>"$LOG_FILE" 2>&1; then
  log "psql returned non-zero — continuing to the sanity checks, which are the real verdict"
fi

if grep -qE '^psql:.*(FATAL|could not connect|out of memory)' "$LOG_FILE"; then
  fail "psql hit a fatal error loading the dump — see $LOG_FILE"
fi

# ── 5. sanity checks — did real data actually come back? ──────────────────────
db="coolify"
docker exec "$PG_CONTAINER" psql -U postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname='$db'" 2>>"$LOG_FILE" | grep -q 1 \
  || fail "database '$db' does not exist after the restore"

for table in "${!MIN_ROWS[@]}"; do
  count="$(docker exec "$PG_CONTAINER" psql -U postgres -d "$db" -tAc \
    "SELECT count(*) FROM public.$table" 2>>"$LOG_FILE" || echo "")"
  [[ "$count" =~ ^[0-9]+$ ]] || fail "table '$table' is missing from the restored database"
  ROW_COUNTS["$table"]="$count"
  (( count >= MIN_ROWS[$table] )) \
    || fail "table '$table' restored with $count rows, expected at least ${MIN_ROWS[$table]}"
  log "  $table: $count rows"
done

STATUS="passed"
DETAIL="restored $DUMP_NAME from snapshot $SNAPSHOT_ID ($SNAPSHOT_TIME) and verified it loads into PostgreSQL with real data"
log "RESTORE VERIFIED"
exit 0
