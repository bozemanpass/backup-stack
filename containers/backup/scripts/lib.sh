#!/usr/bin/env bash
# Shared restic environment setup, sourced by the other scripts.
set -euo pipefail

# Build RESTIC_REPOSITORY from the S3 settings if it was not supplied directly.
# BACKUP_S3_ENDPOINT may include a scheme (http://host:port for a local/test S3 such as
# SeaweedFS); if it has none, https is assumed.
if [ -z "${RESTIC_REPOSITORY:-}" ]; then
  if [ -n "${BACKUP_S3_ENDPOINT:-}" ] && [ -n "${BACKUP_S3_BUCKET:-}" ]; then
    case "${BACKUP_S3_ENDPOINT}" in
      http://*|https://*) base="${BACKUP_S3_ENDPOINT}" ;;
      *)                  base="https://${BACKUP_S3_ENDPOINT}" ;;
    esac
    export RESTIC_REPOSITORY="s3:${base%/}/${BACKUP_S3_BUCKET}"
  else
    echo "backup: no RESTIC_REPOSITORY (or BACKUP_S3_ENDPOINT + BACKUP_S3_BUCKET) configured" >&2
    exit 1
  fi
fi

# The encryption key is mandatory: without it the repository cannot be read back.
if [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ]; then
  echo "backup: RESTIC_PASSWORD is not set - refusing to run without an encryption key" >&2
  exit 1
fi

# Ensure the restic repository exists and reads back cleanly, riding out a cold object
# store (e.g. SeaweedFS still warming up) without wedging it. Guards three hazards:
#   - transient read/write failures while the store warms up -> retry with backoff;
#   - a concurrent initializer winning the race (the scheduler container and a manual
#     `backup` run can both land here at once) -> treat a failed `restic init` (including
#     "already initialized") as non-fatal and let the next `restic cat config` confirm it;
#   - building on a half-written / corrupt repo -> require `restic cat config` to succeed
#     before returning, so we never proceed on a config that only partially landed.
# Require a repository that already exists, without creating one.
#
# For reading -- a restore above all -- creating the repository is never the right
# answer: an empty repository restores nothing, so a typo in the repository
# location would otherwise look like a backup with nothing in it rather than like
# the mistake it is. That matters most when the location came from outside (a
# restore from another deployment's backups, via RESTIC_REPOSITORY).
require_repo() {
  if restic cat config >/dev/null 2>&1; then
    return 0
  fi
  echo "backup: no readable restic repository at ${RESTIC_REPOSITORY}" >&2
  echo "backup: (a restore never creates one -- check the repository location)" >&2
  restic cat config >&2 || true
  return 1
}

ensure_repo() {
  local attempts="${BACKUP_INIT_ATTEMPTS:-30}"
  local delay="${BACKUP_INIT_DELAY:-5}"
  local i last_err=""
  for (( i = 1; i <= attempts; i++ )); do
    if restic cat config >/dev/null 2>&1; then
      return 0
    fi
    echo "backup: repository not ready at ${RESTIC_REPOSITORY}, initializing (attempt ${i}/${attempts})"
    # May fail because the store is still warming up or because another initializer got
    # there first; either way, loop and let the check above confirm the repo next pass.
    # Keep the error: transient warmup noise stays quiet, but a persistent failure (e.g. an
    # S3 auth/config problem, not mere warmup) is reported below instead of being swallowed.
    if last_err="$(restic init 2>&1)"; then
      # An init that reports success but whose repository cannot be read back has
      # written a repository that never will be: restic will not init over it, so
      # every later attempt fails on "already initialized" and the loop above can
      # only spin. Seen against an object store that is still coming up, which
      # accepts the writes and returns something else for the reads. Say so here,
      # where the cause is still visible.
      if ! restic cat config >/dev/null 2>&1; then
        echo "backup: created the repository at ${RESTIC_REPOSITORY} but cannot read it back." >&2
        echo "backup: the object store accepted writes it does not serve; it was probably not" >&2
        echo "backup: ready. The repository is unusable and has to be removed from the store" >&2
        echo "backup: before backups can run." >&2
        restic cat config >&2 || true
        return 1
      fi
      return 0
    fi
    sleep "${delay}"
  done
  echo "backup: repository at ${RESTIC_REPOSITORY} not usable after ${attempts} attempts" >&2
  if [ -n "${last_err}" ]; then
    echo "backup: last 'restic init' error:" >&2
    printf '%s\n' "${last_err}" >&2
  fi
  return 1
}
