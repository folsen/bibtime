#!/bin/bash
set -euo pipefail

# BibTime SQLite Backup/Restore Script
# Uses sqlite3 .backup for a safe, consistent backup even while the app is running.
#
# Usage:
#   ./scripts/backup.sh backup [DB_PATH] [BACKUP_DIR]
#   ./scripts/backup.sh restore BACKUP_FILE [DB_PATH]

DB_PATH="${DATABASE_PATH:-bibtime_dev.db}"

backup() {
  local db="${1:-$DB_PATH}"
  local backup_dir="${2:-backups}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="${backup_dir}/bibtime_${timestamp}.db"

  if [ ! -f "$db" ]; then
    echo "Error: Database file not found: $db"
    exit 1
  fi

  mkdir -p "$backup_dir"

  echo "Backing up $db → $backup_file ..."
  sqlite3 "$db" ".backup '$backup_file'"
  echo "Backup complete: $backup_file ($(du -h "$backup_file" | cut -f1))"
}

restore() {
  local backup_file="$1"
  local db="${2:-$DB_PATH}"

  if [ ! -f "$backup_file" ]; then
    echo "Error: Backup file not found: $backup_file"
    exit 1
  fi

  # Verify it's a valid SQLite database
  if ! sqlite3 "$backup_file" "SELECT 1;" > /dev/null 2>&1; then
    echo "Error: $backup_file is not a valid SQLite database"
    exit 1
  fi

  if [ -f "$db" ]; then
    echo "Warning: $db already exists. A backup will be created before overwriting."
    backup "$db" "$(dirname "$db")"
  fi

  echo "Restoring $backup_file → $db ..."
  sqlite3 "$backup_file" ".backup '$db'"
  echo "Restore complete."
}

case "${1:-}" in
  backup)
    backup "${2:-}" "${3:-}"
    ;;
  restore)
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 restore BACKUP_FILE [DB_PATH]"
      exit 1
    fi
    restore "$2" "${3:-}"
    ;;
  *)
    echo "BibTime Database Backup/Restore"
    echo ""
    echo "Usage:"
    echo "  $0 backup [DB_PATH] [BACKUP_DIR]    Create a backup"
    echo "  $0 restore BACKUP_FILE [DB_PATH]     Restore from backup"
    echo ""
    echo "Environment:"
    echo "  DATABASE_PATH    Default database path (current: $DB_PATH)"
    exit 1
    ;;
esac
