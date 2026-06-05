# Grimmory

Self-hosted digital library (community fork of BookLore). Deployed on understairs at
`https://library.homelab.blacksd.tech` in parallel with the existing calibre-web.

Design spec: [`docs/superpowers/specs/2026-06-03-grimmory-design.md`](../../docs/superpowers/specs/2026-06-03-grimmory-design.md)

## Operational notes

### Email is NOT configured via Kustomize / env vars

Grimmory stores email providers as MariaDB rows, not as application config. The
`SendEmailV2Service` constructs a `JavaMailSenderImpl` per row at request time. There
are no `SPRING_MAIL_*` or `SMTP_*` env vars to set on the Deployment, and the upstream
Helm chart does not expose mail settings either.

**To configure email** (e.g., for Send-to-Kindle):

1. Log in to Grimmory as admin.
2. Settings → Email Providers → add an SMTP provider (host, port, username, password,
   from-address, TLS).
3. Add per-user recipients (e.g., `<kindle>@kindle.com`) under Email Recipients.

The settings live in the `grimmory-mariadb` PVC. Deleting that PVC erases them.

### DSM-side prep (one-time, before first rollout)

The NFS share at `/volume1/Apps/grimmory` must exist on the Synology with:

- DSM user `k8s-nfs` (UID 1027, GID 100 = `users`) granted R/W.
- NFS export: no-mapping squash, R/W, async, non-privileged ports allowed, subfolder
  mounts allowed, source IP `192.168.20.0/24`.
- Share contents pre-chowned. SSH to NAS and run:

  ```
  sudo chown -R k8s-nfs:users /volume1/Apps/grimmory/
  sudo chmod -R g+rwsX /volume1/Apps/grimmory/
  sudo mkdir -p /volume1/Apps/grimmory/bookdrop
  sudo chown k8s-nfs:users /volume1/Apps/grimmory/bookdrop
  sudo chmod g+rwsX /volume1/Apps/grimmory/bookdrop
  ```

  `sudo` is required — DSM's SSH shell does not chown shared folders without it.

### Library path inside the container

When adding a library in the Grimmory UI, the path is **`/books`** (or a subdirectory).
Not `/volume1/...` — that's the NAS path, invisible to the container.

BookDrop watches `/bookdrop`, which is a `subPath: bookdrop` mount of the same NFS PVC.
Files dropped via SMB into `/volume1/Apps/grimmory/bookdrop/` on the NAS land there.

### Image source

`docker.io/grimmory/grimmory` (Docker Hub). The project's GHCR repo only publishes
nightlies — stable tags (`v3.x`) live on Docker Hub only. Pin by digest.

The Grimmory entrypoint requires root (it runs `adduser` + `chown` before `su-exec`
drops to `USER_ID:GROUP_ID`). The Deployment's pod-level `securityContext` therefore
sets only `fsGroup: 100`, not `runAsUser`.
