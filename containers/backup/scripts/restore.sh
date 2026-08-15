#!/usr/bin/env bash
# Restore a snapshot into the volume tree.
#
# Usage: restore.sh [snapshot-id] [volume ...]    (default: latest, every volume)
#
# Restore is run as a distinct mode: the full application stack is stopped first and the
# data volumes are mounted READ-WRITE under /backup, so restic writes the chosen epoch's
# data back in place. The full stack is then started again. See ../stack/docs/backup.md.
#
# Naming volumes restores only those, which is what `stack manage ... backup restore
# --volume` passes through. The k8s target restores per volume too (K8up restores one
# claim at a time), so the granularity is the same on both.
#
# RESTIC_REPOSITORY may be set by the caller to restore from a repository other than
# this deployment's own -- `stack manage ... backup restore --from` does exactly that,
# to seed a deployment from an existing backup. lib.sh only derives the repository from
# BACKUP_S3_* when it is not already set, so nothing else here has to know.
set -euo pipefail
source /scripts/lib.sh
require_repo

snapshot="${1:-latest}"
shift || true

include_args=()
for volume in "$@"; do
  include_args+=(--include "/backup/${volume}")
done

if [ ${#include_args[@]} -eq 0 ]; then
  echo "backup: restoring snapshot '${snapshot}' into /backup"
else
  echo "backup: restoring $* from snapshot '${snapshot}' into /backup"
fi
restic restore "$snapshot" --target / "${include_args[@]+"${include_args[@]}"}"

# NOTE: logical dumps land back under /backup/_dumps as files. Replaying them into a live
# database (e.g. pg_restore) is a deliberate follow-up, not yet automated - see the
# "Restore" and open-questions sections of docs/backup.md.
echo "backup: restore complete"
