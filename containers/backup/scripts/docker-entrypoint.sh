#!/usr/bin/env bash
set -euo pipefail
source /scripts/lib.sh

mode="${1:-schedule}"
case "$mode" in
  schedule)
    ensure_repo
    schedule="${BACKUP_SCHEDULE:-0 3 * * *}"
    echo "backup: scheduling '${schedule}'  ->  /scripts/backup.sh"
    # Single cron entry; send job output to PID 1's stdout so it shows in container logs.
    echo "${schedule} /scripts/backup.sh >> /proc/1/fd/1 2>&1" > /etc/crontabs/root
    exec crond -f -l 8
    ;;
  backup)  exec /scripts/backup.sh ;;
  restore) shift; exec /scripts/restore.sh "$@" ;;
  prune)   exec /scripts/prune.sh ;;
  check)   ensure_repo; exec restic check ;;
  *)
    echo "backup: unknown mode '$mode' (expected: schedule|backup|restore|prune|check)" >&2
    exit 2
    ;;
esac
