# Calibre-Web and Audiobookshelf on understairs

Status: draft for review
Author: Marco (with Claude)
Date: 2026-06-02

## Context and motivation

The understairs cluster currently runs `ghostfolio` as a portfolio tracker. It is being removed because Ghostfolio blocks ISINs that Yahoo Finance does not track, which excludes several of Marco's holdings. The portfolio-tracking concern moves off-cluster to Portfolio Performance (desktop, synced file) — see the prior session for rationale.

The slot freed on understairs will be reused for two media apps that have been wanted for a while:

- **Calibre-Web** — read-only-ish web UI over an existing Calibre library, used to browse and download e-books from any device.
- **Audiobookshelf** — self-hosted audiobook and podcast server with a web UI and first-class mobile apps.

Both apps consume a media tree that already exists on Marco's Synology NAS. The cluster mounts that tree via NFSv4; the apps' own state (SQLite, cache, covers, transcode artifacts) lives on local `openebs-rawfile` PVCs.

The existing `apps/ghostfolio/` tree stays on disk for safekeeping; only its entry in `clusters/understairs/kustomization.yaml` is dropped.

## Goals

1. Run Calibre-Web on understairs, backed by Marco's existing Calibre library on the Synology NAS over NFS, reachable at `books.homelab.blacksd.tech` from the LAN and Tailscale.
2. Run Audiobookshelf on understairs, backed by an audiobook directory on the Synology NAS over NFS, reachable at `audiobooks.homelab.blacksd.tech` from the LAN and Tailscale.
3. Remove `ghostfolio` from the understairs Flux Kustomization while keeping `apps/ghostfolio/` intact on disk.
4. Install `csi-driver-nfs` on understairs (via the platform repo) so apps can consume NFS exports as PVs.
5. Follow the existing native-Kustomize app pattern (`apps/<app>/{base,overlays/understairs}` + `clusters/understairs/<app>.yaml`).

## Non-goals

- Setting up the NFS server on the Synology. Export configuration is the user's responsibility; this design only documents the contract the cluster expects.
- Migrating the Calibre library or audiobook files into the cluster. Both stay on the NAS.
- Supporting concurrent writes to the Calibre library from multiple cluster pods or other hosts. Calibre-Web is the only writer to `metadata.db`.
- Standing up backup/replication for the NAS itself.
- A second deployment to `freeloader`. Scope is understairs only.

## Architecture

### Storage model

Each app has two volumes:

- **NFS-backed media volume (RWX)**: the actual library files on the Synology, mounted read-write through `csi-driver-nfs`. Static PV + PVC, defined in the overlay.
- **Local config volume (RWO, `openebs-rawfile`)**: the app's own SQLite, logs, covers cache, transcode artifacts. Dynamic PVC.

SQLite files (`metadata.db` for Calibre-Web, `absdatabase.sqlite` for Audiobookshelf) live as follows:

- Calibre-Web's `metadata.db` lives on **NFS** as part of the Calibre library. This is unavoidable: Calibre desktop and Calibre-Web both expect `metadata.db` at the library root. Risk is acceptable because (a) Calibre-Web is the only cluster-side writer, (b) Marco's Calibre desktop is the other writer but doesn't run concurrently with cluster writes, (c) we mount NFSv4.1 with locking enabled.
- Audiobookshelf's `absdatabase.sqlite` lives in its **config dir on local storage**, never on NFS. Only the audiobook media files go on NFS. This is the clean split Audiobookshelf is designed for.

If Calibre-Web's `metadata.db` corrupts in practice (concurrent-write incident, NFS hiccup), the fallback is to take a backup before changes and rebuild metadata via Calibre desktop. We do not pre-optimize for this.

### Identity / file ownership

All NFS-backed files must be readable and writable as **UID 1000, GID 1000**. This is the linuxserver.io default for Calibre-Web and what we'll explicitly set for Audiobookshelf via `securityContext`.

On the Synology side, the shared folders' NFS export permission must squash all clients to a user/group that owns the files on the NAS:

- DSM → Shared Folder → NFS Permissions → Squash: **Map all users to admin** (or to a dedicated user with UID 1000)
- Ownership of the share contents: UID 1000 / GID 1000

Pod-side, both Deployments set:

```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
```

### Networking

Both apps follow the existing pattern: an `HTTPRoute` attached to the shared `external` Gateway in `envoy-gateway-system`, plus a `SecurityPolicy` allowlisting `192.168.20.0/24` (LAN) and `100.64.0.0/10` (Tailscale).

- `books.homelab.blacksd.tech` → Calibre-Web service
- `audiobooks.homelab.blacksd.tech` → Audiobookshelf service

TLS is terminated at the Gateway (same as other apps; cert-manager handles certs at the platform layer).

### Flux wiring

Two new Flux Kustomizations under `clusters/understairs/`:

```yaml
# clusters/understairs/calibre-web.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: calibre-web
  namespace: flux-system
spec:
  interval: 15m0s
  sourceRef:
    kind: GitRepository
    name: apps
  path: ./apps/calibre-web/overlays/understairs
  prune: true
  wait: true
  timeout: 10m0s
```

Same shape for `audiobookshelf.yaml`. Neither needs `decryption.provider: sops` — there are no encrypted secrets in either app's overlay (NFS auth is host-based, no app-level secrets in scope).

`clusters/understairs/kustomization.yaml` becomes:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - audiobookshelf.yaml
  - calibre-web.yaml
  - minecraft-bedrock.yaml
  - paperless-ngx.yaml
  - vaultwarden.yaml
```

Note: `ghostfolio.yaml` is removed; `apps/ghostfolio/` stays on disk.

## Per-app design

### Calibre-Web

**Image:** `lscr.io/linuxserver/calibre-web:latest` (pinned to a specific digest in the manifest at implementation time).

**Container ports:** 8083 (HTTP).

**Environment:**

- `PUID=1000`, `PGID=1000`, `TZ=Europe/Rome`
- `DOCKER_MODS=linuxserver/mods:universal-calibre` to enable EPUB→other-format conversion via the embedded Calibre tooling (lets Calibre-Web do format conversion server-side without a separate Calibre headless pod)

**Volumes:**

- `/config` → `pvc-calibre-web-config`, openebs-rawfile, **1 GiB**. Holds Calibre-Web's own SQLite (`app.db`, `gdrive.db`), logs, and cache.
- `/books` → `pvc-calibre-web-library`, NFS, **2 GiB** (matches user's sizing for the library on NAS). Bound to a static PV pointing at the Synology export.

**Resources:**

```yaml
requests: { cpu: 50m, memory: 192Mi }
limits:   { cpu: 1000m, memory: 768Mi }
```

Limits are generous because the universal-calibre mod uses Calibre tooling for conversion, which spikes memory.

**Probes:** HTTP GET `/` on port 8083. `startupProbe` with `failureThreshold: 30` because first-run scanning of the library can take time.

**Strategy:** `Recreate` (single RWO config PVC).

### Audiobookshelf

**Image:** `ghcr.io/advplyr/audiobookshelf:latest` (pinned to a specific tag/digest at implementation time).

**Container ports:** 80 (HTTP, app's default).

**Environment:**

- `TZ=Europe/Rome`
- `AUDIOBOOKSHELF_UID=1000`, `AUDIOBOOKSHELF_GID=1000` (the image honors these)

**Volumes:**

- `/config` → `pvc-audiobookshelf-config`, openebs-rawfile, **2 GiB**. Holds `absdatabase.sqlite`, covers cache, sessions.
- `/metadata` → `pvc-audiobookshelf-metadata`, openebs-rawfile, **2 GiB**. Holds transcoded chunks, downloaded podcast episodes the app generates, backups.
- `/audiobooks` → `pvc-audiobookshelf-media`, NFS, **5 GiB**. Bound to a static PV pointing at the Synology export.

`/config` and `/metadata` are split per Audiobookshelf's documented layout — keeping the database separate from the larger derived-content directory makes backups and rebuilds simpler.

**Resources:**

```yaml
requests: { cpu: 50m, memory: 256Mi }
limits:   { cpu: 1000m, memory: 1Gi }
```

Audiobookshelf is heavier than Calibre-Web at idle (Node.js, larger working set). The memory ceiling accommodates occasional ffmpeg-driven transcoding for streaming.

**Probes:** HTTP GET `/healthcheck` on port 80.

**Strategy:** `Recreate` (RWO PVCs).

## NFS PV/PVC definitions

Each app overlay contains a static PV and a PVC that explicitly binds to it. Using static PVs (not a dynamic StorageClass-driven flow) because the export paths are known and fixed, and explicit PVs make the binding obvious in git.

Template for Calibre-Web (`apps/calibre-web/overlays/understairs/pv-library.yaml`):

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: calibre-web-library
spec:
  capacity:
    storage: 2Gi
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  mountOptions:
    - nfsvers=4.1
    - hard
    - nconnect=4
    - rsize=1048576
    - wsize=1048576
  csi:
    driver: nfs.csi.k8s.io
    volumeHandle: calibre-web-library  # any unique string
    volumeAttributes:
      server: <NAS_HOSTNAME_OR_IP>     # from user
      share: <CALIBRE_EXPORT_PATH>     # from user, e.g. /volume1/calibre-library
```

Matching PVC (`pvc-library.yaml`):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: calibre-web-library
  namespace: calibre-web
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ""
  resources:
    requests:
      storage: 2Gi
  volumeName: calibre-web-library
```

Same shape for Audiobookshelf with `5Gi` and its own export path.

The `<NAS_HOSTNAME_OR_IP>` and `<CALIBRE_EXPORT_PATH>` / `<AUDIOBOOKSHELF_EXPORT_PATH>` placeholders are filled in at implementation time using values the user provides.

## Platform repo work

The cluster needs `csi-driver-nfs` installed. This is platform-level concern and belongs in `~/Repositories/platform/`, not in `apps`. Specifically:

- Install `csi-driver-nfs` via its official Helm chart (chart `csi-driver-nfs` from `https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts`), pinned version.
- Place under `infrastructure/<some-tier>/csi-driver-nfs/` following whatever pattern the platform repo uses for other infrastructure pieces.
- Add a corresponding Flux Kustomization under `clusters/understairs/`.
- No StorageClass is required for static PVs — the PV references the CSI driver directly via `csi.driver: nfs.csi.k8s.io`. Optionally, also create a StorageClass for future dynamic-provisioning use, but it's not load-bearing for this design.

A subagent dispatched against the platform repo handles this in parallel with this work. The apps in this design assume the driver is present; if it's not, the PVCs stay `Pending` until it's installed (acceptable failure mode, doesn't block Flux for other apps).

## Ghostfolio removal

Single edit to `clusters/understairs/kustomization.yaml`: remove the `- ghostfolio.yaml` line. Leave `clusters/understairs/ghostfolio.yaml` on disk for safekeeping per user request. Leave `apps/ghostfolio/` entirely on disk.

Flux will prune the live ghostfolio resources on next reconcile (because `prune: true` on the Flux Kustomization that's about to disappear is the wrong mental model — what actually happens is: the *parent* `clusters/understairs/kustomization.yaml` no longer references the child Flux Kustomization, so flux-system reconciles that delta and removes the child Kustomization resource, which in turn (since it has `prune: true`) removes everything it owned: namespace, CNPG cluster, deployment, etc.).

**Caveat:** the CNPG Cluster's underlying PVC may or may not be reclaimed depending on PV reclaim policy. This is acceptable — the user explicitly asked to scrap Ghostfolio.

## File inventory

New files:

```
apps/calibre-web/base/namespace.yaml
apps/calibre-web/base/deployment.yaml
apps/calibre-web/base/kustomization.yaml
apps/calibre-web/overlays/understairs/kustomization.yaml
apps/calibre-web/overlays/understairs/pv-library.yaml
apps/calibre-web/overlays/understairs/pvc-library.yaml
apps/calibre-web/overlays/understairs/pvc-config.yaml
apps/calibre-web/overlays/understairs/httproute.yaml

apps/audiobookshelf/base/namespace.yaml
apps/audiobookshelf/base/deployment.yaml
apps/audiobookshelf/base/kustomization.yaml
apps/audiobookshelf/overlays/understairs/kustomization.yaml
apps/audiobookshelf/overlays/understairs/pv-media.yaml
apps/audiobookshelf/overlays/understairs/pvc-media.yaml
apps/audiobookshelf/overlays/understairs/pvc-config.yaml
apps/audiobookshelf/overlays/understairs/pvc-metadata.yaml
apps/audiobookshelf/overlays/understairs/httproute.yaml

clusters/understairs/calibre-web.yaml
clusters/understairs/audiobookshelf.yaml
```

Modified files:

```
clusters/understairs/kustomization.yaml   (- ghostfolio, + audiobookshelf, + calibre-web)
```

Platform repo (separate PR via subagent):

```
infrastructure/<tier>/csi-driver-nfs/...   (Helm-based install)
clusters/understairs/csi-driver-nfs.yaml   (Flux Kustomization)
```

## Inputs required from user before implementation

1. **NFS server hostname or IP** for the Synology (e.g., `synology.lan` or `192.168.20.x`).
2. **NFS export path for the Calibre library** (e.g., `/volume1/calibre-library`).
3. **NFS export path for the audiobook library** (e.g., `/volume1/audiobooks`).
4. **Confirmation** that the Synology NFS exports squash to UID 1000 / GID 1000 (or that file ownership on the NAS is already 1000:1000 with no squash).

## Risks

- **SQLite over NFS for Calibre-Web's `metadata.db`.** Mitigated by single-writer assumption and NFSv4.1 with locking. Backup before any Calibre desktop session that touches the library while the pod is running.
- **`csi-driver-nfs` not present yet.** If the platform PR is not merged before the apps PR, PVCs stay `Pending` and the Deployments don't progress. This is a visible, recoverable failure mode, not silent corruption.
- **UID/GID mismatch on Synology.** First-run permission denied is the obvious symptom. Fixed by adjusting the Synology export squash settings, not by changing the cluster manifests.
- **Universal-calibre mod size.** The linuxserver Calibre-Web image with `DOCKER_MODS=linuxserver/mods:universal-calibre` adds several hundred MB of Calibre tooling at pod startup. First pull is slow on understairs hardware; subsequent pulls are cached.

## Out-of-scope follow-ups

- A dynamic StorageClass for NFS for future use by other apps.
- Calibre headless server-in-browser (KasmVNC pattern) if Calibre-Web's metadata editing turns out to be insufficient.
- Audiobookshelf podcast feeds, OPDS for Calibre-Web — both are enabled by default in their respective apps; no extra config required, but documenting that they're not goals of this design.
