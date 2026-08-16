#!/usr/bin/env bash
# Back up the mounted data volumes, one snapshot per volume.
#
# `stack deploy` mounts each of the deployment's volumes at /data/<volume>, and each is
# backed up on its own, so a snapshot holds exactly one volume and its path inside the
# snapshot is /data/<volume>.
#
# Both of those match what K8up does on the Kubernetes target, deliberately: it is what
# makes a repository written here restorable there and vice versa, since each side finds
# what it is looking for at the path it expects. See docs/backup.md in the stack repo.
set -euo pipefail
source /scripts/lib.sh
ensure_repo

# 1. Take the logical dumps. Each streams into a snapshot of its own, independent of the
#    volume snapshots below -- so this is not a step the volume backup depends on, and
#    the order of the two does not matter. It runs first only so that a failing dump
#    fails the backup before it has spent time on the volumes.
/scripts/run-hooks.sh
# Counted so that a stack whose only backup artifact is a dump -- a database that
# excludes its data directory, which is the arrangement the documentation recommends --
# is not reported below as a backup with nothing in it.
dumped=$( printf '%s\n' "${BACKUP_PRE_HOOKS:-}" | grep -c '[^[:space:]]' || true )

# 2. Back up each mounted volume as its own snapshot. A volume with nothing in it is still
#    worth a snapshot: restoring it should empty the target, not leave whatever is there.
backed_up=0
for volume_dir in /data/*/; do
  [ -d "$volume_dir" ] || continue
  volume=$( basename "$volume_dir" )
  echo "backup: starting restic backup of ${volume}"
  restic backup --host "${STACK_DEPLOYMENT:-stack}" "/data/${volume}"
  backed_up=$(( backed_up + 1 ))
done

if [ "$backed_up" -eq 0 ] && [ "$dumped" -eq 0 ]; then
  # No volumes and no dumps: the deployment has nothing to back up, or nothing reached
  # this container. Silently writing an empty repository would look exactly like a
  # working backup.
  echo "backup: no volumes are mounted under /data and no dump commands are configured" >&2
  exit 1
fi

# 3. Apply the retention policy.
/scripts/prune.sh

echo "backup: complete (${backed_up} volumes, ${dumped} dumps)"
