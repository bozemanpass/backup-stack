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
# in the same deployment.
self_id="$(grep -o -m1 '[0-9a-f]\{64\}' /proc/self/cgroup || true)"
project="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$self_id" 2>/dev/null || true)"

while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  read -r svc ext cmd <<< "$entry"
  if [ -z "$svc" ] || [ -z "$ext" ] || [ -z "$cmd" ]; then
    echo "backup: malformed BACKUP_PRE_HOOKS entry '${entry}' - skipping" >&2
    continue
  fi

  cid="$(docker ps -q \
      --filter "label=com.docker.compose.project=${project}" \
      --filter "label=com.docker.compose.service=${svc}" | head -n1)"
  if [ -z "$cid" ]; then
    echo "backup: hook target service '${svc}' not found - skipping" >&2
    continue
  fi

  echo "backup: dumping '${svc}' (${cmd})"
  docker exec "$cid" sh -c "$cmd" > "${dump_dir}/${svc}.${ext}"
done <<< "$hooks"
