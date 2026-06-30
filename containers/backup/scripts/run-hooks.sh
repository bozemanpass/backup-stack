#!/usr/bin/env bash
# Run per-service consistency-dump commands *inside* their containers (via the Docker
# socket) and write the output under /backup/_dumps so restic captures a consistent
# logical backup alongside the file-level volume data.
#
# BACKUP_PRE_HOOKS format:  "service:command:ext;service2:command2:ext2"
#   e.g.  "db:pg_dump -U postgres -d todos:sql"
set -euo pipefail

hooks="${BACKUP_PRE_HOOKS:-}"
[ -z "$hooks" ] && exit 0

dump_dir="/backup/_dumps"
mkdir -p "$dump_dir"

# Resolve the compose project of THIS container, so hooks only exec into sibling services
# in the same deployment.
self_id="$(grep -o -m1 '[0-9a-f]\{64\}' /proc/self/cgroup || true)"
project="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$self_id" 2>/dev/null || true)"

IFS=';' read -ra entries <<< "$hooks"
for entry in "${entries[@]}"; do
  [ -z "$entry" ] && continue
  svc="${entry%%:*}"; rest="${entry#*:}"
  cmd="${rest%:*}"; ext="${rest##*:}"

  cid="$(docker ps -q \
      --filter "label=com.docker.compose.project=${project}" \
      --filter "label=com.docker.compose.service=${svc}" | head -n1)"
  if [ -z "$cid" ]; then
    echo "backup: hook target service '${svc}' not found - skipping" >&2
    continue
  fi

  echo "backup: dumping '${svc}' (${cmd})"
  docker exec "$cid" sh -c "$cmd" > "${dump_dir}/${svc}.${ext}"
done
