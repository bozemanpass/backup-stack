#!/usr/bin/env bash
# List the snapshots in the repository, one per line, oldest first:
#
#     <id><TAB><date><TAB><volume>,<volume>,...
#
# This format is a contract with the stack tool, which prints it for
# `stack manage ... backup list` and parses the id out of it for a restore. The
# Kubernetes target builds the same three fields from K8up's Snapshot objects, so
# what an operator sees does not depend on which target the deployment is on.
#
# The volume names are the top-level directories inside /backup in the snapshot,
# which is one per backed-up volume -- so a volume the stack author excluded is
# visibly absent here rather than merely undocumented.
set -euo pipefail
source /scripts/lib.sh
ensure_repo

# --json rather than the table output: the table is meant for people and its
# column widths move with the data.
restic snapshots --json | jq -r '.[] | [.short_id, .time] | @tsv' | while IFS=$'\t' read -r id time; do
  volumes=$(restic ls "$id" 2>/dev/null | sed -n 's|^/backup/\([^/]*\)$|\1|p' | paste -sd, -)
  printf '%s\t%s\t%s\n' "$id" "$time" "$volumes"
done
