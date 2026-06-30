#!/usr/bin/env bash
set -euo pipefail
source /scripts/lib.sh

# Word-splitting of $retention is intentional (the flags are passed through to restic).
retention="${BACKUP_RETENTION:---keep-daily 7 --keep-weekly 4 --keep-monthly 6}"
echo "backup: applying retention (${retention})"
# shellcheck disable=SC2086
restic forget --prune $retention
