#!/usr/bin/env bash
# Query Better Stack production logs via the ClickHouse-compatible SQL API.
#
# Designed for AI agents (and humans) to debug prod issues without leaving
# the terminal. Logs are shipped from Fly to Better Stack by the
# fly-log-shipper app — see DEPLOY.md for the shipper setup.
#
# Usage:
#   scripts/logs.sh tail [N]                last N entries (default 50)
#   scripts/logs.sh errors [N]              last N error/critical entries
#   scripts/logs.sh search <text> [N]       rows containing <text> (case-insensitive)
#   scripts/logs.sh recent <minutes> [N]    rows from the last <minutes> minutes
#   scripts/logs.sh request <request_id>    rows for a specific Phoenix request_id
#   scripts/logs.sh schema                  list columns available on the source table
#   scripts/logs.sh sql "<SQL>"             run a raw ClickHouse query
#
# Set BETTERSTACK_DEBUG=1 to echo the SQL to stderr before each request.
#
# Env vars (load from .env or export before running):
#   BETTERSTACK_QUERY_HOST       e.g. eu-nbg-2-connect.betterstackdata.com
#   BETTERSTACK_QUERY_USERNAME   Basic Auth username (Better Stack → Integrations → SQL API)
#   BETTERSTACK_QUERY_PASSWORD   Basic Auth password
#   BETTERSTACK_QUERY_TABLE      e.g. t123456_bibtime_prod_logs
#
# Output is one JSON object per line (FORMAT JSONEachRow), pipe through `jq`
# for pretty-printing: scripts/logs.sh tail | jq

set -euo pipefail

# Load .env if present so credentials don't have to be exported manually.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/../.env"
  set +a
fi

require_env() {
  local missing=()
  for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD BETTERSTACK_QUERY_TABLE; do
    if [ -z "${!v:-}" ]; then
      missing+=("$v")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing required env vars: ${missing[*]}" >&2
    echo "See the header of $0 or DEPLOY.md for setup." >&2
    exit 1
  fi
}

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

run_sql() {
  local sql="$1"
  if [ "${BETTERSTACK_DEBUG:-}" = "1" ]; then
    echo "SQL: $sql" >&2
  fi
  # No -f: we want to see ClickHouse's error body on 4xx/5xx, not just exit code.
  local response status
  response=$(curl -sS -w '\n__HTTP_STATUS__%{http_code}' \
    -u "${BETTERSTACK_QUERY_USERNAME}:${BETTERSTACK_QUERY_PASSWORD}" \
    -H 'Content-type: text/plain' \
    -X POST \
    "https://${BETTERSTACK_QUERY_HOST}/?output_format_pretty_row_numbers=0" \
    --data-binary "$sql")
  status="${response##*__HTTP_STATUS__}"
  body="${response%__HTTP_STATUS__*}"
  printf '%s' "$body"
  if [ "$status" -ge 400 ]; then
    echo "" >&2
    echo "HTTP $status from ${BETTERSTACK_QUERY_HOST}" >&2
    echo "SQL: $sql" >&2
    return 1
  fi
}

cmd="${1:-}"
case "$cmd" in
  tail)
    require_env
    n="${2:-50}"
    run_sql "SELECT dt, raw FROM remote(${BETTERSTACK_QUERY_TABLE}) ORDER BY dt DESC LIMIT ${n} FORMAT JSONEachRow"
    ;;
  errors)
    require_env
    n="${2:-50}"
    run_sql "SELECT dt, raw FROM remote(${BETTERSTACK_QUERY_TABLE}) WHERE raw ILIKE '%[error]%' OR raw ILIKE '%** (%' OR raw ILIKE '%exception%' ORDER BY dt DESC LIMIT ${n} FORMAT JSONEachRow"
    ;;
  search)
    require_env
    [ -n "${2:-}" ] || usage
    needle="$2"
    n="${3:-50}"
    safe_needle="${needle//\'/\'\'}"
    run_sql "SELECT dt, raw FROM remote(${BETTERSTACK_QUERY_TABLE}) WHERE raw ILIKE '%${safe_needle}%' ORDER BY dt DESC LIMIT ${n} FORMAT JSONEachRow"
    ;;
  recent)
    require_env
    [ -n "${2:-}" ] || usage
    minutes="$2"
    n="${3:-200}"
    run_sql "SELECT dt, raw FROM remote(${BETTERSTACK_QUERY_TABLE}) WHERE dt >= now() - INTERVAL ${minutes} MINUTE ORDER BY dt DESC LIMIT ${n} FORMAT JSONEachRow"
    ;;
  request)
    require_env
    [ -n "${2:-}" ] || usage
    rid="${2//\'/\'\'}"
    run_sql "SELECT dt, raw FROM remote(${BETTERSTACK_QUERY_TABLE}) WHERE raw ILIKE '%request_id=${rid}%' ORDER BY dt ASC LIMIT 500 FORMAT JSONEachRow"
    ;;
  schema)
    require_env
    run_sql "DESCRIBE TABLE remote(${BETTERSTACK_QUERY_TABLE}) FORMAT JSONEachRow"
    ;;
  sql)
    require_env
    [ -n "${2:-}" ] || usage
    run_sql "$2"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    ;;
esac
