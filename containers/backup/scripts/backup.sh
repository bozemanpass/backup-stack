#!/usr/bin/env bash
set -euo pipefail
source /scripts/lib.sh
ensure_repo

# 1. Run consistency hooks (logical dumps) into the backup tree.
/scripts/run-hooks.sh

# 2. Back up everything mounted under /backup: the read-only data volumes plus any dumps.
echo "backup: starting restic backup of /backup"
restic backup --host "${STACK_DEPLOYMENT:-stack}" /backup

# 3. Apply the retention policy.
/scripts/prune.sh

echo "backup: complete"
