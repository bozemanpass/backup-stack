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

# Create the repository on first use (idempotent).
ensure_repo() {
  if ! restic cat config >/dev/null 2>&1; then
    echo "backup: initializing restic repository at ${RESTIC_REPOSITORY}"
    restic init
  fi
}
