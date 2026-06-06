# Linkwarden deployment on understairs

Status: draft for review
Author: Marco (with Claude)
Date: 2026-06-06

## Context and motivation

Linkwarden is a self-hosted bookmark manager with page archiving (PDF, PNG, HTML, readability view) and tagging. The understairs cluster already runs the home stack (vaultwarden, paperless-ngx, audiobookshelf, grimmory, homepage, minecraft-bedrock); Linkwarden slots into "Tools" alongside vaultwarden and paperless-ngx as another personal-knowledge utility.

There is **no official Helm chart** from the Linkwarden project. Three community charts exist (FMJ Studios, soubenz, 0hlov3/schoenwald), all single-maintainer with varying maturity. The decision is to ship Linkwarden as **native Kustomize manifests** following the Grimmory pattern: full control, no third-party chart drift, fits the cluster's mixed-pattern reality where stable upstream charts (vaultwarden, paperless-ngx) use HelmRelease and chartless apps use hand-written manifests.

## Goals

1. Run Linkwarden on understairs, reachable at `links.homelab.blacksd.tech` from LAN and Tailscale.
2. Back Linkwarden with a dedicated single-instance CNPG `Cluster`, same shape as vaultwarden's `vaultwarden-pg`.
3. Local accounts only. First-user bootstrap via open registration, then a follow-up commit disables registration.
4. Add a homepage tile under "Tools" pointing at the new hostname.
5. Follow the native-Kustomize app pattern (`apps/<app>/{base,overlays/understairs}` + `clusters/understairs/<app>.yaml`).

## Non-goals

- **Meilisearch.** Linkwarden's full-text search of archived page content depends on Meilisearch as a sidecar. Skipped to keep the footprint small on the mini PCs. Title/tag/URL search still works. Can be added later by introducing a second Deployment + PVC + four env vars (`MEILI_HOST`, `MEILI_MASTER_KEY`, `NEXT_PUBLIC_MEILISEARCH_URL`, `MEILI_ENV`).
- **Zitadel OIDC.** Out of scope. Linkwarden supports OIDC; wiring it up requires a Zitadel application set up too. Deferred until the Zitadel app-configuration pattern is established in the repo.
- **CNPG backups.** No Barman/object-store backup configured. Matches vaultwarden's current state. A cross-cluster CNPG backup strategy is worth its own initiative rather than per-app.
- **High availability.** Single Postgres instance, single Linkwarden replica, `Recreate` strategy.
- **Deployment to `freeloader`.** Scope is understairs only.
- **Admin account pre-seeding via env vars.** Open registration handles bootstrap; one follow-up commit disables it. Avoids a SOPS file for credentials nobody ever reads back.

## Architecture

### Components

Single namespace `linkwarden` holds:

- **`linkwarden` Deployment** — Next.js app. Mounts `/data/data` (local PVC, openebs-rawfile) for archived pages, screenshots, PDFs, profile photos. Reads DB credentials from the CNPG-generated `linkwarden-pg-app` Secret. Reads `NEXTAUTH_SECRET` from a Secret produced by an External Secrets `Password` generator.
- **`linkwarden-pg` CNPG `Cluster`** — single instance, openebs-rawfile, bootstrap `database: linkwarden, owner: linkwarden`. Matches `vaultwarden-pg` shape.
- **`linkwarden` Service** — `ClusterIP`, port 80 → container port 3000.
- **`HTTPRoute`** — `links.homelab.blacksd.tech` → linkwarden svc, attached to the shared `external` Gateway in `envoy-gateway-system`. No path split (Linkwarden has no separate admin panel), no `SecurityPolicy` (the app is auth-gated and exposed publicly to allow sharing collections).

### Storage model

| Volume               | Type            | Size  | Purpose                                          |
|----------------------|-----------------|-------|--------------------------------------------------|
| `pvc-linkwarden-data`| openebs-rawfile | 10 GiB| `/data/data` — archived pages, PDFs, screenshots |
| CNPG-managed PVC     | openebs-rawfile | 2 GiB | `linkwarden-pg` Postgres datadir                 |

The data PVC is sized at 10 GiB to give Linkwarden headroom for archived PDFs without going overboard. It can be expanded later via PVC patch — openebs-rawfile supports online expansion.

### Secrets

- **`NEXTAUTH_SECRET`** — generated in-cluster by an External Secrets `Password` generator (length 48), mirroring `apps/vaultwarden/overlays/understairs/admin-token.externalsecret.yaml`. Resulting Secret name `linkwarden-nextauth-secret`, key `secret`.
- **`DATABASE_URL`** — sourced from the CNPG-managed `linkwarden-pg-app` Secret (`uri` key). Wired into the Deployment as `valueFrom.secretKeyRef`.

No SOPS file is needed: nothing here is operator-supplied secret material.

### Networking

Single `HTTPRoute`, mirroring vaultwarden's public route minus the admin split:

```yaml
hostnames: [links.homelab.blacksd.tech]
backendRefs: [{ name: linkwarden, port: 80 }]
parentRefs: [{ name: external, namespace: envoy-gateway-system }]
```

No `SecurityPolicy`. Linkwarden supports public sharing of collections, so an IP allowlist would defeat one of its features. The login wall is the only protection, which matches the threat model used for vaultwarden's public routes.

### Flux wiring

New `clusters/understairs/linkwarden.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: linkwarden
  namespace: flux-system
spec:
  interval: 15m0s
  sourceRef:
    kind: GitRepository
    name: apps
  path: ./apps/linkwarden/overlays/understairs
  prune: true
  wait: true
  timeout: 10m0s
```

No `decryption.provider: sops` — no SOPS files in this overlay.

`clusters/understairs/kustomization.yaml` gains `- linkwarden.yaml`.

## Per-component design

### Linkwarden Deployment

**Image:** `ghcr.io/linkwarden/linkwarden:v2.11.4` pinned at implementation time (confirm current stable from the repo's Releases page at write time; the upstream `docker-compose.yml` ships `:latest`, but we always pin).

**Container port:** 3000 (Linkwarden default).

**Environment** (names verified against Linkwarden's upstream `docker-compose.yml` and `.env.sample`):

- `NEXTAUTH_URL=https://links.homelab.blacksd.tech`
- `NEXTAUTH_SECRET` — from Secret `linkwarden-nextauth-secret`, key `secret`
- `DATABASE_URL` — from Secret `linkwarden-pg-app`, key `uri`
- `NEXT_PUBLIC_DISABLE_REGISTRATION=false` (initial state; flipped to `true` in a follow-up commit after first user signup)
- `TZ=Europe/Rome`

Meilisearch-related env vars (`MEILI_HOST`, `MEILI_MASTER_KEY`, `NEXT_PUBLIC_MEILISEARCH_URL`) are deliberately unset.

**Volume:**

- `/data/data` → `pvc-linkwarden-data` (openebs-rawfile, 10 GiB)

Note the mount path: upstream `docker-compose.yml` maps `./data:/data/data`. The container internally uses `/data/data` (not `/data`) as the data root.

**Resources:**

```yaml
requests: { cpu: 100m, memory: 512Mi }
limits:   { cpu: 1000m, memory: 1Gi }
```

Linkwarden runs a Node.js process plus a headless Chromium worker for page archiving. The 1 GiB ceiling fits a low-traffic personal instance; archiving spikes will be brief.

**Probes:** HTTP GET `/api/v1/users` returns 401 unauthenticated but is reachable without login, making it a usable readiness signal. Linkwarden does not expose a dedicated health endpoint.

```yaml
startupProbe:
  httpGet: { path: /api/v1/users, port: http }
  failureThreshold: 30
  periodSeconds: 10
livenessProbe:
  tcpSocket: { port: http }
  periodSeconds: 30
readinessProbe:
  httpGet: { path: /api/v1/users, port: http }
  periodSeconds: 10
```

Liveness uses TCP rather than HTTP to avoid killing the pod during long-running archive jobs that may block the Node event loop briefly. Startup `failureThreshold: 30` (5 minutes) for first-start Prisma migrations.

**Strategy:** `Recreate` (RWO PVC, single replica).

**SecurityContext:** Linkwarden image runs as a non-root user by default. No `runAsUser` override — the data PVC is fresh openebs-rawfile with no pre-existing ownership constraints, and `fsGroup` is unnecessary because the image's own user owns the volume after first write.

**initContainer:** A `busybox` initContainer that waits for the CNPG service `linkwarden-pg-rw:5432` to accept TCP. Cheap insurance against first-start race with the Postgres bootstrap. CNPG normally has the cluster ready well before Linkwarden's pod is scheduled, but the wait costs nothing.

### CNPG Cluster

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: linkwarden-pg
  namespace: linkwarden
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16.2
  storage:
    storageClass: openebs-rawfile
    size: 2Gi
  resources:
    requests: { memory: 128Mi, cpu: 50m }
    limits:   { memory: 256Mi, cpu: 250m }
  bootstrap:
    initdb:
      database: linkwarden
      owner: linkwarden
  postgresql:
    parameters:
      max_worker_processes: "4"
      max_parallel_workers: "2"
      max_replication_slots: "8"
      max_slot_wal_keep_size: "512MB"
  priorityClassName: system-cluster-critical
```

Same shape as `vaultwarden-pg`. The `bootstrap.initdb.owner: linkwarden` setting creates the `linkwarden` role with a generated password, exposed via the `linkwarden-pg-app` Secret (CNPG convention: `<cluster>-app`). No separate `Database` CR is needed because the `initdb` block already creates the database and owner — the `cnpg-database-cr.md` gotcha applies only when you use a `Database` CR without setting `bootstrap.initdb`.

### Service definition

```yaml
ports: [{ name: http, port: 80, targetPort: 3000 }]
```

## File inventory

New files:

```
apps/linkwarden/base/namespace.yaml
apps/linkwarden/base/deployment.yaml
apps/linkwarden/base/service.yaml
apps/linkwarden/base/kustomization.yaml

apps/linkwarden/overlays/understairs/kustomization.yaml
apps/linkwarden/overlays/understairs/pvc-data.yaml
apps/linkwarden/overlays/understairs/cluster.cnpg.yaml
apps/linkwarden/overlays/understairs/nextauth-secret.externalsecret.yaml
apps/linkwarden/overlays/understairs/httproute.yaml

clusters/understairs/linkwarden.yaml
```

The data PVC lives in the overlay because `openebs-rawfile` is cluster-specific. The base would lock storage decisions; keeping the PVC overlay-side preserves the option of a different storage class on a future cluster (e.g., `freeloader` may have different options).

Modified files:

```
clusters/understairs/kustomization.yaml                       (+ linkwarden.yaml)
apps/homepage/overlays/understairs/config/services.yaml       (+ Linkwarden entry under Tools)
```

## Inputs (to confirm at implementation time)

- Exact current Linkwarden release tag from the GitHub Releases page; pin to a specific version (not `latest`).
- That `/api/v1/users` is reachable without auth on the version being deployed — confirm by reading the Next.js route file in the upstream repo at the pinned tag. If it requires auth, fall back to a TCP-only readiness probe.
- Whether Linkwarden still uses Prisma migrations on startup at the pinned version (it does at v2.x; verify it hasn't changed). Determines whether startupProbe needs to allow more time.
- DNS — confirm `links.homelab.blacksd.tech` is wired in the same external DNS provider as the other `*.homelab.blacksd.tech` hostnames before merge.

## Risks

- **Single Postgres instance, no backups.** Same risk profile as vaultwarden. Bookmark loss would be annoying but not catastrophic; mitigated long-term by adopting a cross-cluster CNPG backup strategy.
- **Page archives live only on the PVC.** No external backup. If the data PVC is lost, archives are gone. Users can re-archive a URL but lose any pages that have rotted off the open web. Acceptable for a personal instance; would not be acceptable for a multi-user archival project.
- **Public hostname with no IP allowlist.** Linkwarden's login wall is the only barrier. Mitigation: `NEXT_PUBLIC_DISABLE_REGISTRATION=true` after first user signup, strong password chosen at registration time. Acceptable.
- **No Meilisearch means search is shallow.** Title, tag, URL only — not archived page content. Documented limitation. Search-over-content can be enabled later without data migration.
- **`:latest` drift if pinning is forgotten.** Mitigation: implementation must pin a specific version tag, no `:latest` in the merged manifests.

## Out-of-scope follow-ups

- **Disable registration after first signup.** Single-line patch flipping `NEXT_PUBLIC_DISABLE_REGISTRATION` to `true` once Marco has registered his account. Land as a follow-up commit on the same branch or as a separate small PR.
- **Meilisearch.** If full-text search of archived content becomes valuable. Adds a second Deployment + PVC + four env vars on the Linkwarden side. Generate `MEILI_MASTER_KEY` via an ExternalSecret `Password` generator.
- **Zitadel OIDC.** Once the Zitadel application-configuration pattern is established in the repo, wire Linkwarden via the standard OIDC env vars (`NEXT_PUBLIC_AUTHENTIK_ENABLED`-style vars, confirm against Linkwarden docs at the time).
- **CNPG backups.** A cross-cluster initiative covering vaultwarden-pg, linkwarden-pg, and paperless-ngx-pg (if applicable) — Barman to a Backblaze B2 / R2 bucket. Out of scope here.
- **Homepage widget.** Linkwarden does not currently have a gethomepage.dev widget. If one ships upstream, add it to the homepage tile.
