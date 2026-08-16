#!/usr/bin/env bash
# Run per-service consistency-dump commands *inside* their containers (via the Docker
# socket) and stream each one's stdout straight into restic as a snapshot of its own.
#
# This is what a "backup command" means, here and in K8up: the command's **stdout is the
# backup**. It is not a hook that quiesces a volume so that the file-level backup of it is
# consistent -- that would be a different feature, needing the dump to be written before
# the volumes are read, and neither engine offers it. K8up in particular snapshots the
# PVCs independently of the annotated command, so a command whose useful effect is a file
# it writes into a volume is captured a backup late there, or not at all. Streaming is
# the model both engines actually implement, so it is the model stack exposes.
#
# BACKUP_PRE_HOOKS holds one entry per line:
#
#     <service> <extension> <command...>
#
# e.g.  "db sql pg_dump -U postgres -d todos"
#
# The service name and extension are single words; the command is the tail of the
# line, so it may contain anything but a newline. This format is a contract with
# `stack deploy`, which writes it from the stack's `@stack backup-command` /
# `@stack backup-file-extension` annotations (see docs/backup.md in the stack repo).
#
# Each dump becomes a snapshot named "<deployment>-<service>.<extension>", which is the
# shape K8up gives the same dump on the other target, so `backup list` reads the same on
# both and either engine's repository can be read by the other.
set -euo pipefail

hooks="${BACKUP_PRE_HOOKS:-}"
[ -z "$hooks" ] && exit 0

source /scripts/lib.sh

# Resolve the compose project of THIS container, so hooks only exec into sibling services
# in the same deployment. Compose sets a container's hostname to its own id, which docker
# inspect resolves to the project label. (/proc/self/cgroup is no use here: under cgroup
# v2 it is just "0::/", with no container id in it.) The fallback is STACK_DEPLOYMENT,
# which `stack deploy` injects with the deployment's name -- the same value it uses as
# the compose project name.
project="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$(hostname)" 2>/dev/null || true)"
project="${project:-${STACK_DEPLOYMENT:-}}"
if [ -z "$project" ]; then
  echo "backup: cannot resolve this deployment's compose project - refusing to back up without its dumps" >&2
  exit 1
fi

while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  read -r svc ext cmd <<< "$entry"
  if [ -z "$svc" ] || [ -z "$ext" ] || [ -z "$cmd" ]; then
    echo "backup: malformed BACKUP_PRE_HOOKS entry '${entry}'" >&2
    exit 1
  fi

  cid="$(docker ps -q \
      --filter "label=com.docker.compose.project=${project}" \
      --filter "label=com.docker.compose.service=${svc}" | head -n1)"
  if [ -z "$cid" ]; then
    # A backup taken without its dump would look exactly like a working one, which is
    # the failure mode this whole mechanism exists to prevent -- so fail the backup.
    echo "backup: hook target service '${svc}' not found in project '${project}'" >&2
    exit 1
  fi

  echo "backup: dumping '${svc}' (${cmd})"
  # Streamed rather than buffered to a file first, so a dump larger than this
  # container's disk is still possible -- which is the point of a logical backup of a
  # big database. The cost is that a command failing halfway has already handed restic
  # the bytes it produced: `set -o pipefail` makes that fail the backup loudly, but the
  # short snapshot is written. A failed backup whose last snapshot cannot be trusted is
  # the same bargain K8up makes for the same reason.
  docker exec "$cid" sh -c "$cmd" \
    | restic backup --stdin --stdin-filename "${project}-${svc}.${ext}" --host "${STACK_DEPLOYMENT:-stack}"
done <<< "$hooks"
