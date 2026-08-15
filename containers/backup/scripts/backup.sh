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

# 1. Run consistency hooks (logical dumps) into the backup tree.
/scripts/run-hooks.sh

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

if [ "$backed_up" -eq 0 ]; then
  # Nothing is mounted, so the deployment has no volumes or none reached this container.
  # Silently writing an empty repository would look exactly like a working backup.
  echo "backup: no volumes are mounted under /data - nothing to back up" >&2
  exit 1
fi

# 3. Apply the retention policy.
/scripts/prune.sh

echo "backup: complete (${backed_up} volumes)"
