#!/usr/bin/env bash
# List the snapshots in the repository, one per line, oldest first:
#
#     <id><TAB><date><TAB><volume>,<volume>,...
#
# This format is a contract with the stack tool, which prints it for
# `stack manage ... backup list` and parses the id out of it for a restore. The Kubernetes
# target builds the same three fields from K8up's Snapshot objects, so what an operator
# sees does not depend on which target the deployment is on.
#
# A snapshot holds one volume, so the last column is normally a single name -- it stays a
# list because the format is shared with the other target, and because a repository may
# still hold snapshots taken when a backup covered several volumes at once.
#
# The volume names come from the snapshot's own paths (/data/<volume>), so a volume the
# stack author excluded is visibly absent here rather than merely undocumented.
set -euo pipefail
source /scripts/lib.sh
ensure_repo

# --json rather than the table output: the table is meant for people and its column widths
# move with the data.
restic snapshots --json \
  | jq -r '.[] | [.short_id, .time, ([.paths[] | sub("^/data/"; "")] | join(","))] | @tsv'
