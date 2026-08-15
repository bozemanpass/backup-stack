# backup-stack

Backup and restore of persistent service data for the
[`stack`](https://github.com/bozemanpass/stack) tool's Docker deployment mode.

> **Status: in use.** Built and exercised end-to-end by `tests/backup/run-test.sh` in the `stack` repo,
> which is where the documentation lives: `docs/backup.md`.

## What this provides

`bozemanpass/backup` — a small Alpine image bundling:

- [restic](https://restic.net) — the backup engine: mandatory client-side encryption, deduplication, and
  native S3 support, so commodity object storage can be used safely;
- a cron scheduler;
- the Docker CLI — used to run application-consistency hooks (e.g. `pg_dump`) *inside* the target service
  container, the same way the ingress proxy uses the Docker socket.

On Kubernetes the equivalent role is played by [K8up](https://k8up.io), also restic-based. This repo covers
the Docker case only, and the two are not currently interchangeable: both write ordinary restic
repositories, but this one takes a single snapshot of `/backup` holding every volume, where K8up takes one
snapshot per volume under `/data/<volume>`. Either is readable with the `restic` CLI; neither target's
restore understands the other's layout.

## Layout

| Path | Purpose |
|------|---------|
| `stacks/backup/stack.yml` | Stack definition — declares the container and the pod. |
| `backup/composefile.yml` | The canonical `backup` service. `stack deploy` appends mounts of the application's data volumes here when backup is enabled -- read-write, because restoring writes back through them. |
| `containers/backup/` | The `bozemanpass/backup` image: `Containerfile`, `build.sh`, and `scripts/`. |

## Container modes

The image entrypoint takes a mode argument (default `schedule`):

| Mode | Action |
|------|--------|
| `schedule` | Install a cron entry (`BACKUP_SCHEDULE`) that runs `backup` periodically. |
| `backup` | Run hooks, then `restic backup` of `/backup`, then apply retention. |
| `restore [snapshot] [volume…]` | Restore a snapshot into the (rw-mounted) volumes, all of them or only those named. Default `latest`. Never creates a repository: restoring from one that is not there is a mistake, not an empty backup. |
| `list` | One `<id> <date> <volume,volume>` line per snapshot -- the format `stack manage … backup list` prints. |
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
| `BACKUP_PRE_HOOKS` | `service:command:ext;…` consistency dumps. Scaffolded here but **never set by `stack`** -- the annotations that would generate it are parsed no further; see "Not built yet" in `docs/backup.md`. |
| `RESTIC_REPOSITORY` | Set directly to override where a run reads/writes, which is how `backup restore --from` points one restore at another deployment's repository. |

## Build &amp; use

```bash
stack fetch repo bozemanpass/backup-stack
stack prepare --stack backup          # builds bozemanpass/backup:stack
# Backup is then enabled per-deployment via the `backup` config switch; see docs/backup.md.
```
