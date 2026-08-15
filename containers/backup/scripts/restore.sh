#!/usr/bin/env bash
# Restore volumes from the repository.
#
# Usage: restore.sh [snapshot-id] [volume ...]    (default: latest, every mounted volume)
#
# The data volumes are mounted READ-WRITE at /data/<volume>, which is also the path a
# snapshot records, so restic writes each volume's files back exactly where they came from
# with no path juggling. The same holds for a repository written by K8up on the Kubernetes
# target, which uses the same layout -- that is the point of it.
#
# Naming volumes restores only those, which is what `stack manage ... backup restore
# --volume` passes through. The k8s target restores per volume too, so the granularity is
# the same on both.
#
# RESTIC_REPOSITORY may be set by the caller to restore from a repository other than this
# deployment's own -- `stack manage ... backup restore --from` does exactly that, to seed a
# deployment from an existing backup. lib.sh only derives the repository from BACKUP_S3_*
# when it is not already set, so nothing else here has to know.
set -euo pipefail
source /scripts/lib.sh
require_repo

snapshot="${1:-latest}"
shift || true

volumes=("$@")
named=1
if [ ${#volumes[@]} -eq 0 ]; then
  # Which volumes to fill comes from what this deployment mounts, not from what the
  # repository holds: the request is "fill my volumes from that backup", and when the
  # backup is another deployment's there is no reason its contents should decide.
  named=0
  for volume_dir in /data/*/; do
    [ -d "$volume_dir" ] || continue
    volumes+=( "$( basename "$volume_dir" )" )
  done
fi

if [ ${#volumes[@]} -eq 0 ]; then
  echo "backup: no volumes are mounted under /data - nothing to restore into" >&2
  exit 1
fi

if [ "$snapshot" != "latest" ]; then
  # A snapshot holds exactly one volume, so naming one names the volume too. Its path
  # inside the snapshot is where it is mounted, so it lands back in place.
  echo "backup: restoring snapshot '${snapshot}'"
  restic restore "$snapshot" --target /
  echo "backup: restore complete"
  exit 0
fi

# "latest" has to be resolved per volume: the newest snapshot in the repository holds
# whichever volume was backed up last, so restic is asked for the newest snapshot *of each
# path* instead. K8up's restore does the same thing on the other target.
failed=()
for volume in "${volumes[@]}"; do
  echo "backup: restoring ${volume} from the latest snapshot of it"
  if ! restic restore latest --path "/data/${volume}" --target /; then
    if [ "$named" -eq 1 ]; then
      # Asked for by name: its absence is the answer to what was asked.
      echo "backup: no snapshot of ${volume} in ${RESTIC_REPOSITORY}" >&2
      exit 1
    fi
    # Inferred: a volume the backup does not hold is expected -- one added since the
    # backup was taken, or a backup from a stack that never had it. Say so and carry on,
    # so one absent volume does not abandon the rest half restored.
    echo "backup: no snapshot of ${volume}, skipping" >&2
    failed+=( "$volume" )
  fi
done

if [ ${#failed[@]} -eq ${#volumes[@]} ]; then
  echo "backup: nothing could be restored from ${RESTIC_REPOSITORY}" >&2
  exit 1
fi

echo "backup: restore complete"
