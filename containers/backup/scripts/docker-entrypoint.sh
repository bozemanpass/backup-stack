#!/usr/bin/env bash
set -euo pipefail
source /scripts/lib.sh

mode="${1:-schedule}"
case "$mode" in
  schedule)
    # Deliberately does not create the repository here. The scheduler starts with
    # the rest of the deployment, which is the moment the object store is least
    # likely to be ready -- and a repository created against a store that is not
    # ready is unreadable ever after (see ensure_repo). The first backup creates
    # it, by which time the store has had the whole schedule interval to come up.
    schedule="${BACKUP_SCHEDULE:-0 3 * * *}"
    echo "backup: scheduling '${schedule}'  ->  /scripts/backup.sh"
    # Single cron entry; send job output to PID 1's stdout so it shows in container logs.
    echo "${schedule} /scripts/backup.sh >> /proc/1/fd/1 2>&1" > /etc/crontabs/root
    exec crond -f -l 8
    ;;
  backup)  exec /scripts/backup.sh ;;
  restore) shift; exec /scripts/restore.sh "$@" ;;
  list)    exec /scripts/list.sh ;;
  prune)   exec /scripts/prune.sh ;;
  check)   ensure_repo; exec restic check ;;
  *)
    echo "backup: unknown mode '$mode' (expected: schedule|backup|restore|list|prune|check)" >&2
    exit 2
    ;;
esac
