#!/usr/bin/env bash
# Run per-service consistency-dump commands *inside* their containers (via the Docker
# socket) and write the output under /data/_dumps so restic captures a consistent
# logical backup alongside the file-level volume data.
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
set -euo pipefail

hooks="${BACKUP_PRE_HOOKS:-}"
[ -z "$hooks" ] && exit 0

dump_dir="/data/_dumps"
mkdir -p "$dump_dir"

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
  docker exec "$cid" sh -c "$cmd" > "${dump_dir}/${svc}.${ext}"
done <<< "$hooks"
