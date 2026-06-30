#!/usr/bin/env bash
# Restore a snapshot into the volume tree.
#
# Usage: restore.sh [snapshot-id]    (default: latest)
#
# Restore is run as a distinct mode: the full application stack is stopped first and the
# data volumes are mounted READ-WRITE under /backup, so restic writes the chosen epoch's
# data back in place. The full stack is then started again. See ../stack/docs/backup.md.
set -euo pipefail
source /scripts/lib.sh
ensure_repo

snapshot="${1:-latest}"
echo "backup: restoring snapshot '${snapshot}' into /backup"
restic restore "$snapshot" --target /

# NOTE: logical dumps land back under /backup/_dumps as files. Replaying them into a live
# database (e.g. pg_restore) is a deliberate follow-up, not yet automated - see the
# "Restore" and open-questions sections of docs/backup.md.
echo "backup: restore complete"
