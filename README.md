# backup-stack

Backup and restore of persistent service data for the
[`stack`](https://github.com/bozemanpass/stack) tool's Docker deployment mode.

> **Status: initial scaffold — not yet functional.** The container scripts are a starting point and have
> not been run end-to-end. See the design in the `stack` repo: `docs/backup.md` and
> `docs/backup-implementation.md`.

## What this provides

`bozemanpass/backup` — a small Alpine image bundling:

- [restic](https://restic.net) — the backup engine: mandatory client-side encryption, deduplication, and
  native S3 support, so commodity object storage can be used safely;
- a cron scheduler;
- the Docker CLI — used to run application-consistency hooks (e.g. `pg_dump`) *inside* the target service
  container, the same way the ingress proxy uses the Docker socket.

On Kubernetes the equivalent role is played by [K8up](https://k8up.io) (also restic-based), so the two
targets produce interchangeable repositories. This repo covers the Docker case only.

## Layout

| Path | Purpose |
|------|---------|
| `stacks/backup/stack.yml` | Stack definition — declares the container and the pod. |
| `backup/composefile.yml` | The canonical `backup` service. `stack deploy` injects read-only mounts of the application's data volumes here when backup is enabled. |
| `containers/backup/` | The `bozemanpass/backup` image: `Containerfile`, `build.sh`, and `scripts/`. |

## Container modes

The image entrypoint takes a mode argument (default `schedule`):

| Mode | Action |
|------|--------|
| `schedule` | Install a cron entry (`BACKUP_SCHEDULE`) that runs `backup` periodically. |
| `backup` | Run hooks, then `restic backup` of `/backup`, then apply retention. |
| `restore [snapshot]` | Restore a snapshot into the (rw-mounted) volumes. Default `latest`. |
| `prune` | Apply the retention policy (`restic forget --prune`). |
| `check` | Verify repository integrity. |

## Configuration

Supplied by `stack` from the deployment environment (see `docs/backup.md` for the profile keys):

| Variable | Purpose |
|----------|---------|
| `BACKUP_S3_ENDPOINT`, `BACKUP_S3_BUCKET` | Object store location (or set `RESTIC_REPOSITORY` directly). |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Object store credentials. |
| `RESTIC_PASSWORD` | **Encryption key** — mandatory. Without it the repository is unreadable. |
| `BACKUP_SCHEDULE` | Cron schedule (default `0 3 * * *`). |
| `BACKUP_RETENTION` | `forget`/`prune` flags (default `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`). |
| `BACKUP_PRE_HOOKS` | `service:command:ext;…` consistency dumps, generated from `@stack backup-command` annotations. |

## Build &amp; use (intended)

```bash
stack fetch repo bozemanpass/backup-stack
stack prepare --stack backup          # builds bozemanpass/backup:stack
# Backup is then enabled per-deployment via the `backup` config switch; see docs/backup.md.
```
