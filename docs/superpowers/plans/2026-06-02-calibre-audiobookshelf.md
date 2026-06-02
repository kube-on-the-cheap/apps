# Calibre-Web and Audiobookshelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Calibre-Web and Audiobookshelf to the `understairs` cluster, backed by NFS exports from a Synology NAS, and remove Ghostfolio from the cluster's Flux Kustomization while keeping its manifests on disk.

**Architecture:** Native Kustomize per app, following the existing `apps/<name>/{base,overlays/understairs}` + `clusters/understairs/<name>.yaml` pattern. Each app gets local `openebs-rawfile` PVCs for its own state and a static NFS PV/PVC for media. `csi-driver-nfs` (already prepared in the platform repo) provides the NFS CSI driver. No Helm charts; both apps have well-behaved upstream images.

**Tech Stack:** Kubernetes, Flux (GitOps), Kustomize, csi-driver-nfs, envoy-gateway (HTTPRoute + SecurityPolicy), openebs-rawfile StorageClass, linuxserver.io Calibre-Web image, advplyr/audiobookshelf image.

---

## Prerequisites (not part of this plan, must be done before execution)

1. **Platform repo PR merged and reconciled.** The `csi-driver-nfs` install is on branch `feat/csi-driver-nfs-understairs` in `~/Repositories/platform/` (commit `53fac7e`). It must be pushed, merged, and Flux must have reconciled it on understairs before the PVCs in this plan will bind. Verify with:
   ```
   kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-nfs
   kubectl get csidrivers nfs.csi.k8s.io
   ```
   Expected: pods Running on at least `minipc1`; CSIDriver exists.

2. **Synology setup complete.** Per the spec:
   - DSM user `k8s-nfs` exists (UID 1027, GID 100 / `users`).
   - Shared folders `/volume1/Apps/calibre-library` and `/volume1/Apps/audiobookshelf-media` exist.
   - NFS export on each: Squash "No mapping", R/W, async, non-privileged ports allowed, subfolder access allowed, source `192.168.20.0/24`.
   - NFSv4 enabled in DSM, domain `homelab.blacksd.tech`.
   - On the NAS: `chown -R k8s-nfs:users <share>` and `chmod -R g+rwsX <share>` for each share.

3. **DNS records:** `books.homelab.blacksd.tech` and `audiobooks.homelab.blacksd.tech` resolve to the understairs Gateway's external IP. (Same DNS pattern as existing apps; user-managed.)

If any prereq is not in place, stop and fix it before running this plan — the manifests will deploy but the apps will fail to start.

---

## Verification Tooling

Throughout this plan, "verify" steps use:
- `kustomize build <overlay-path>` — lints the manifest set, exits non-zero on bad YAML or unresolved references. The user has `devbox` configured; `kustomize` is on PATH.
- `kubectl --context understairs ...` — for live cluster inspection. Assumed the user's kubeconfig has an `understairs` context.
- Flux reconciliation is **not** triggered manually by this plan. Tasks 11–14 are integration verification after the user has merged the PR and Flux has reconciled.

---

## File Inventory

**New files:**

```
apps/calibre-web/base/namespace.yaml
apps/calibre-web/base/deployment.yaml
apps/calibre-web/base/kustomization.yaml

apps/calibre-web/overlays/understairs/kustomization.yaml
apps/calibre-web/overlays/understairs/pvc-config.yaml
apps/calibre-web/overlays/understairs/pv-library.yaml
apps/calibre-web/overlays/understairs/pvc-library.yaml
apps/calibre-web/overlays/understairs/httproute.yaml

apps/audiobookshelf/base/namespace.yaml
apps/audiobookshelf/base/deployment.yaml
apps/audiobookshelf/base/kustomization.yaml

apps/audiobookshelf/overlays/understairs/kustomization.yaml
apps/audiobookshelf/overlays/understairs/pvc-config.yaml
apps/audiobookshelf/overlays/understairs/pvc-metadata.yaml
apps/audiobookshelf/overlays/understairs/pv-media.yaml
apps/audiobookshelf/overlays/understairs/pvc-media.yaml
apps/audiobookshelf/overlays/understairs/httproute.yaml

clusters/understairs/calibre-web.yaml
clusters/understairs/audiobookshelf.yaml
```

**Modified files:**

```
clusters/understairs/kustomization.yaml   (- ghostfolio.yaml, + audiobookshelf.yaml, + calibre-web.yaml)
```

---

### Task 1: Create Calibre-Web base namespace and Deployment

**Files:**
- Create: `apps/calibre-web/base/namespace.yaml`
- Create: `apps/calibre-web/base/deployment.yaml`

- [ ] **Step 1: Write the namespace manifest**

`apps/calibre-web/base/namespace.yaml`:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: calibre-web
```

- [ ] **Step 2: Write the Deployment + Service manifest**

`apps/calibre-web/base/deployment.yaml`:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: calibre-web
  namespace: calibre-web
  labels:
    app.kubernetes.io/name: calibre-web
    app.kubernetes.io/component: web
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: calibre-web
      app.kubernetes.io/component: web
  template:
    metadata:
      labels:
        app.kubernetes.io/name: calibre-web
        app.kubernetes.io/component: web
    spec:
      securityContext:
        runAsUser: 1027
        runAsGroup: 100
        fsGroup: 100
      containers:
        - name: calibre-web
          image: lscr.io/linuxserver/calibre-web:0.6.24
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8083
              protocol: TCP
          env:
            - name: PUID
              value: "1027"
            - name: PGID
              value: "100"
            - name: UMASK
              value: "002"
            - name: TZ
              value: "Europe/Rome"
            - name: DOCKER_MODS
              value: "linuxserver/mods:universal-calibre"
          volumeMounts:
            - name: config
              mountPath: /config
            - name: books
              mountPath: /books
          resources:
            requests:
              cpu: 50m
              memory: 192Mi
            limits:
              cpu: 1000m
              memory: 768Mi
          startupProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 30
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: http
            periodSeconds: 30
            failureThreshold: 3
            timeoutSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: http
            periodSeconds: 10
            failureThreshold: 3
            timeoutSeconds: 5
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: calibre-web-config
        - name: books
          persistentVolumeClaim:
            claimName: calibre-web-library
---
apiVersion: v1
kind: Service
metadata:
  name: calibre-web
  namespace: calibre-web
spec:
  selector:
    app.kubernetes.io/name: calibre-web
    app.kubernetes.io/component: web
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add apps/calibre-web/base/namespace.yaml apps/calibre-web/base/deployment.yaml
git commit -m "feat(calibre-web): add base namespace and Deployment"
```

---

### Task 2: Create Calibre-Web base Kustomization

**Files:**
- Create: `apps/calibre-web/base/kustomization.yaml`

- [ ] **Step 1: Write the base kustomization**

`apps/calibre-web/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
```

- [ ] **Step 2: Verify the base builds**

Run:

```bash
kustomize build apps/calibre-web/base
```

Expected: clean YAML output containing the Namespace, Deployment, and Service. No errors. The PVC references in the Deployment will not resolve (PVCs are defined in the overlay) but `kustomize build` doesn't validate references — only YAML and resource ordering.

- [ ] **Step 3: Commit**

```bash
git add apps/calibre-web/base/kustomization.yaml
git commit -m "feat(calibre-web): wire base kustomization"
```

---

### Task 3: Create Calibre-Web overlay PVCs (config + library)

**Files:**
- Create: `apps/calibre-web/overlays/understairs/pvc-config.yaml`
- Create: `apps/calibre-web/overlays/understairs/pv-library.yaml`
- Create: `apps/calibre-web/overlays/understairs/pvc-library.yaml`

- [ ] **Step 1: Write the local config PVC**

`apps/calibre-web/overlays/understairs/pvc-config.yaml`:

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: calibre-web-config
  namespace: calibre-web
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: openebs-rawfile
  resources:
    requests:
      storage: 1Gi
```

- [ ] **Step 2: Write the static NFS PV for the library**

`apps/calibre-web/overlays/understairs/pv-library.yaml`:

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: calibre-web-library
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteMany
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
    volumeHandle: calibre-web-library
    volumeAttributes:
      server: nas.homelab.blacksd.tech
      share: /volume1/Apps/calibre-library
```

- [ ] **Step 3: Write the matching PVC bound to the static PV**

`apps/calibre-web/overlays/understairs/pvc-library.yaml`:

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: calibre-web-library
  namespace: calibre-web
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 2Gi
  volumeName: calibre-web-library
```

- [ ] **Step 4: Commit**

```bash
git add apps/calibre-web/overlays/understairs/pvc-config.yaml \
        apps/calibre-web/overlays/understairs/pv-library.yaml \
        apps/calibre-web/overlays/understairs/pvc-library.yaml
git commit -m "feat(calibre-web): add overlay PVCs for config and NFS library"
```

---

### Task 4: Create Calibre-Web overlay HTTPRoute + SecurityPolicy

**Files:**
- Create: `apps/calibre-web/overlays/understairs/httproute.yaml`

- [ ] **Step 1: Write the HTTPRoute and SecurityPolicy**

`apps/calibre-web/overlays/understairs/httproute.yaml`:

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: calibre-web
  namespace: calibre-web
spec:
  parentRefs:
    - name: external
      namespace: envoy-gateway-system
  hostnames:
    - books.homelab.blacksd.tech
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: calibre-web
          port: 80
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: calibre-web-ip-filter
  namespace: calibre-web
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: calibre-web
  authorization:
    defaultAction: Deny
    rules:
      - action: Allow
        principal:
          clientCIDRs:
            - 192.168.20.0/24
            - 100.64.0.0/10
```

- [ ] **Step 2: Commit**

```bash
git add apps/calibre-web/overlays/understairs/httproute.yaml
git commit -m "feat(calibre-web): expose via HTTPRoute with IP allowlist"
```

---

### Task 5: Wire Calibre-Web overlay Kustomization and verify build

**Files:**
- Create: `apps/calibre-web/overlays/understairs/kustomization.yaml`

- [ ] **Step 1: Write the overlay kustomization**

`apps/calibre-web/overlays/understairs/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
  - pvc-config.yaml
  - pv-library.yaml
  - pvc-library.yaml
  - httproute.yaml
```

- [ ] **Step 2: Verify the overlay builds end-to-end**

Run:

```bash
kustomize build apps/calibre-web/overlays/understairs
```

Expected: clean YAML output containing the Namespace, Deployment, Service, both PVCs, the PV, the HTTPRoute, and the SecurityPolicy. No errors.

Sanity check the output:

```bash
kustomize build apps/calibre-web/overlays/understairs | grep -E '^kind:' | sort
```

Expected (counts may vary; types should match):
```
kind: Deployment
kind: HTTPRoute
kind: Namespace
kind: PersistentVolume
kind: PersistentVolumeClaim
kind: PersistentVolumeClaim
kind: SecurityPolicy
kind: Service
```

- [ ] **Step 3: Commit**

```bash
git add apps/calibre-web/overlays/understairs/kustomization.yaml
git commit -m "feat(calibre-web): wire understairs overlay"
```

---

### Task 6: Create Audiobookshelf base namespace and Deployment

**Files:**
- Create: `apps/audiobookshelf/base/namespace.yaml`
- Create: `apps/audiobookshelf/base/deployment.yaml`

- [ ] **Step 1: Write the namespace manifest**

`apps/audiobookshelf/base/namespace.yaml`:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: audiobookshelf
```

- [ ] **Step 2: Write the Deployment + Service manifest**

`apps/audiobookshelf/base/deployment.yaml`:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: audiobookshelf
  namespace: audiobookshelf
  labels:
    app.kubernetes.io/name: audiobookshelf
    app.kubernetes.io/component: web
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: audiobookshelf
      app.kubernetes.io/component: web
  template:
    metadata:
      labels:
        app.kubernetes.io/name: audiobookshelf
        app.kubernetes.io/component: web
    spec:
      securityContext:
        runAsUser: 1027
        runAsGroup: 100
        fsGroup: 100
      containers:
        - name: audiobookshelf
          image: ghcr.io/advplyr/audiobookshelf:2.16.2
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          env:
            - name: TZ
              value: "Europe/Rome"
            - name: AUDIOBOOKSHELF_UID
              value: "1027"
            - name: AUDIOBOOKSHELF_GID
              value: "100"
          volumeMounts:
            - name: config
              mountPath: /config
            - name: metadata
              mountPath: /metadata
            - name: audiobooks
              mountPath: /audiobooks
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          startupProbe:
            httpGet:
              path: /healthcheck
              port: http
            initialDelaySeconds: 15
            periodSeconds: 10
            failureThreshold: 30
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthcheck
              port: http
            periodSeconds: 30
            failureThreshold: 3
            timeoutSeconds: 10
          readinessProbe:
            httpGet:
              path: /healthcheck
              port: http
            periodSeconds: 10
            failureThreshold: 3
            timeoutSeconds: 5
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: audiobookshelf-config
        - name: metadata
          persistentVolumeClaim:
            claimName: audiobookshelf-metadata
        - name: audiobooks
          persistentVolumeClaim:
            claimName: audiobookshelf-media
---
apiVersion: v1
kind: Service
metadata:
  name: audiobookshelf
  namespace: audiobookshelf
spec:
  selector:
    app.kubernetes.io/name: audiobookshelf
    app.kubernetes.io/component: web
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add apps/audiobookshelf/base/namespace.yaml apps/audiobookshelf/base/deployment.yaml
git commit -m "feat(audiobookshelf): add base namespace and Deployment"
```

---

### Task 7: Create Audiobookshelf base Kustomization

**Files:**
- Create: `apps/audiobookshelf/base/kustomization.yaml`

- [ ] **Step 1: Write the base kustomization**

`apps/audiobookshelf/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
```

- [ ] **Step 2: Verify the base builds**

Run:

```bash
kustomize build apps/audiobookshelf/base
```

Expected: clean YAML output, no errors.

- [ ] **Step 3: Commit**

```bash
git add apps/audiobookshelf/base/kustomization.yaml
git commit -m "feat(audiobookshelf): wire base kustomization"
```

---

### Task 8: Create Audiobookshelf overlay PVCs (config + metadata + media)

**Files:**
- Create: `apps/audiobookshelf/overlays/understairs/pvc-config.yaml`
- Create: `apps/audiobookshelf/overlays/understairs/pvc-metadata.yaml`
- Create: `apps/audiobookshelf/overlays/understairs/pv-media.yaml`
- Create: `apps/audiobookshelf/overlays/understairs/pvc-media.yaml`

- [ ] **Step 1: Write the local config PVC**

`apps/audiobookshelf/overlays/understairs/pvc-config.yaml`:

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: audiobookshelf-config
  namespace: audiobookshelf
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: openebs-rawfile
  resources:
    requests:
      storage: 2Gi
```

- [ ] **Step 2: Write the local metadata PVC**

`apps/audiobookshelf/overlays/understairs/pvc-metadata.yaml`:

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: audiobookshelf-metadata
  namespace: audiobookshelf
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: openebs-rawfile
  resources:
    requests:
      storage: 2Gi
```

- [ ] **Step 3: Write the static NFS PV for the media**

`apps/audiobookshelf/overlays/understairs/pv-media.yaml`:

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: audiobookshelf-media
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
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
    volumeHandle: audiobookshelf-media
    volumeAttributes:
      server: nas.homelab.blacksd.tech
      share: /volume1/Apps/audiobookshelf-media
```

- [ ] **Step 4: Write the matching PVC bound to the static PV**

`apps/audiobookshelf/overlays/understairs/pvc-media.yaml`:

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: audiobookshelf-media
  namespace: audiobookshelf
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 5Gi
  volumeName: audiobookshelf-media
```

- [ ] **Step 5: Commit**

```bash
git add apps/audiobookshelf/overlays/understairs/pvc-config.yaml \
        apps/audiobookshelf/overlays/understairs/pvc-metadata.yaml \
        apps/audiobookshelf/overlays/understairs/pv-media.yaml \
        apps/audiobookshelf/overlays/understairs/pvc-media.yaml
git commit -m "feat(audiobookshelf): add overlay PVCs for config, metadata, NFS media"
```

---

### Task 9: Create Audiobookshelf overlay HTTPRoute + SecurityPolicy

**Files:**
- Create: `apps/audiobookshelf/overlays/understairs/httproute.yaml`

- [ ] **Step 1: Write the HTTPRoute and SecurityPolicy**

`apps/audiobookshelf/overlays/understairs/httproute.yaml`:

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: audiobookshelf
  namespace: audiobookshelf
spec:
  parentRefs:
    - name: external
      namespace: envoy-gateway-system
  hostnames:
    - audiobooks.homelab.blacksd.tech
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: audiobookshelf
          port: 80
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: audiobookshelf-ip-filter
  namespace: audiobookshelf
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: audiobookshelf
  authorization:
    defaultAction: Deny
    rules:
      - action: Allow
        principal:
          clientCIDRs:
            - 192.168.20.0/24
            - 100.64.0.0/10
```

- [ ] **Step 2: Commit**

```bash
git add apps/audiobookshelf/overlays/understairs/httproute.yaml
git commit -m "feat(audiobookshelf): expose via HTTPRoute with IP allowlist"
```

---

### Task 10: Wire Audiobookshelf overlay Kustomization and verify build

**Files:**
- Create: `apps/audiobookshelf/overlays/understairs/kustomization.yaml`

- [ ] **Step 1: Write the overlay kustomization**

`apps/audiobookshelf/overlays/understairs/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
  - pvc-config.yaml
  - pvc-metadata.yaml
  - pv-media.yaml
  - pvc-media.yaml
  - httproute.yaml
```

- [ ] **Step 2: Verify the overlay builds end-to-end**

Run:

```bash
kustomize build apps/audiobookshelf/overlays/understairs
```

Expected: clean YAML output containing the Namespace, Deployment, Service, three PVCs, the PV, the HTTPRoute, and the SecurityPolicy. No errors.

Sanity check:

```bash
kustomize build apps/audiobookshelf/overlays/understairs | grep -E '^kind:' | sort | uniq -c
```

Expected:
```
   1 kind: Deployment
   1 kind: HTTPRoute
   1 kind: Namespace
   1 kind: PersistentVolume
   3 kind: PersistentVolumeClaim
   1 kind: SecurityPolicy
   1 kind: Service
```

- [ ] **Step 3: Commit**

```bash
git add apps/audiobookshelf/overlays/understairs/kustomization.yaml
git commit -m "feat(audiobookshelf): wire understairs overlay"
```

---

### Task 11: Add Flux Kustomization for Calibre-Web

**Files:**
- Create: `clusters/understairs/calibre-web.yaml`

- [ ] **Step 1: Write the Flux Kustomization**

`clusters/understairs/calibre-web.yaml`:

```yaml
---
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

- [ ] **Step 2: Commit**

```bash
git add clusters/understairs/calibre-web.yaml
git commit -m "feat(understairs): add calibre-web Flux Kustomization"
```

---

### Task 12: Add Flux Kustomization for Audiobookshelf

**Files:**
- Create: `clusters/understairs/audiobookshelf.yaml`

- [ ] **Step 1: Write the Flux Kustomization**

`clusters/understairs/audiobookshelf.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: audiobookshelf
  namespace: flux-system
spec:
  interval: 15m0s
  sourceRef:
    kind: GitRepository
    name: apps
  path: ./apps/audiobookshelf/overlays/understairs
  prune: true
  wait: true
  timeout: 10m0s
```

- [ ] **Step 2: Commit**

```bash
git add clusters/understairs/audiobookshelf.yaml
git commit -m "feat(understairs): add audiobookshelf Flux Kustomization"
```

---

### Task 13: Swap Ghostfolio out and Calibre-Web + Audiobookshelf in on understairs

**Files:**
- Modify: `clusters/understairs/kustomization.yaml`

- [ ] **Step 1: Read the current cluster kustomization**

Run:

```bash
cat clusters/understairs/kustomization.yaml
```

Expected current content:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ghostfolio.yaml
  - minecraft-bedrock.yaml
  - paperless-ngx.yaml
  - vaultwarden.yaml
```

- [ ] **Step 2: Replace the file contents**

Replace `clusters/understairs/kustomization.yaml` with:

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

Note: `ghostfolio.yaml` is removed from this list but the file `clusters/understairs/ghostfolio.yaml` and the directory `apps/ghostfolio/` remain on disk untouched, per user request.

- [ ] **Step 3: Verify the cluster kustomization builds**

Run:

```bash
kustomize build clusters/understairs
```

Expected: clean YAML containing four Flux `Kustomization` resources (`audiobookshelf`, `calibre-web`, `minecraft-bedrock`, `paperless-ngx`, `vaultwarden`). No `ghostfolio` Flux Kustomization in the output.

```bash
kustomize build clusters/understairs | grep -E '^  name:' | sort
```

Expected:
```
  name: audiobookshelf
  name: calibre-web
  name: minecraft-bedrock
  name: paperless-ngx
  name: vaultwarden
```

- [ ] **Step 4: Confirm ghostfolio source files are still on disk**

Run:

```bash
ls clusters/understairs/ghostfolio.yaml apps/ghostfolio/
```

Expected: file exists, directory contents listed. No errors. These are preserved on purpose; they're simply no longer referenced from the cluster kustomization.

- [ ] **Step 5: Commit**

```bash
git add clusters/understairs/kustomization.yaml
git commit -m "feat(understairs): wire calibre-web and audiobookshelf, drop ghostfolio"
```

---

### Task 14: Push branch and open the apps PR

**Files:** none modified; orchestration only.

- [ ] **Step 1: Confirm the local commit graph is what you expect**

Run:

```bash
git log --oneline main..HEAD
```

Expected: 13 commits, in this order, one per task above (Task 1 → Task 13). If the graph differs, stop and investigate before pushing.

- [ ] **Step 2: Push the branch**

The user works from `main` (per their git config and the existing repo state). For this multi-commit change, push to a feature branch:

```bash
git checkout -b feat/understairs-calibre-audiobookshelf
git push -u origin feat/understairs-calibre-audiobookshelf
```

If the user prefers committing directly to main (their repo history suggests they sometimes do), confirm with them before deviating from this branch flow.

- [ ] **Step 3: Open the PR**

```bash
gh pr create --title "feat(understairs): add calibre-web and audiobookshelf, remove ghostfolio" --body "$(cat <<'EOF'
## Summary

- Adds Calibre-Web at `books.homelab.blacksd.tech`, backed by the Synology NFS export `/volume1/Apps/calibre-library`.
- Adds Audiobookshelf at `audiobooks.homelab.blacksd.tech`, backed by `/volume1/Apps/audiobookshelf-media`.
- Removes the `ghostfolio` entry from the understairs cluster kustomization. The `apps/ghostfolio/` directory and `clusters/understairs/ghostfolio.yaml` are kept on disk for safekeeping.

## Prerequisites

- Platform repo PR (`feat/csi-driver-nfs-understairs`, commit `53fac7e`) must be merged and reconciled first — these manifests reference `nfs.csi.k8s.io`.
- DSM: `k8s-nfs` user (UID 1027, GID 100) created, both shared folders created and exported with "No mapping" squash, NAS-side `chown k8s-nfs:users` + `chmod g+rwsX` applied.

## Test plan

- [ ] `kustomize build apps/calibre-web/overlays/understairs` succeeds
- [ ] `kustomize build apps/audiobookshelf/overlays/understairs` succeeds
- [ ] `kustomize build clusters/understairs` succeeds
- [ ] After merge: Flux reconciles both Kustomizations to Ready
- [ ] Both PVCs bind; both Deployments reach Available
- [ ] `books.homelab.blacksd.tech` serves the Calibre-Web UI from LAN/Tailscale
- [ ] `audiobooks.homelab.blacksd.tech` serves the Audiobookshelf UI from LAN/Tailscale
- [ ] Both pods can read and write into their NFS-backed volumes (verify by exec into pod, `touch /books/.write-test` for Calibre-Web, then remove it)
- [ ] `ghostfolio` Flux Kustomization is pruned from the cluster
EOF
)"
```

Expected: PR URL printed. Capture it for the user.

- [ ] **Step 4: Report back to the user**

In your message back to the user, include:
- The PR URL.
- A reminder that the platform PR must be merged first.
- The integration verification steps (Task 15) to run after both PRs are merged and reconciled.

---

### Task 15: Post-merge integration verification

**Files:** none. This task runs against the live cluster *after* both PRs are merged and Flux has reconciled.

- [ ] **Step 1: Confirm csi-driver-nfs is running**

Run:

```bash
kubectl --context understairs -n kube-system get pods -l app.kubernetes.io/name=csi-driver-nfs
kubectl --context understairs get csidrivers nfs.csi.k8s.io
```

Expected: controller pod Running, node DaemonSet pod Running on `minipc1`. `CSIDriver` resource exists.

If not: the platform PR hasn't been merged or reconciled yet. Stop here.

- [ ] **Step 2: Confirm Flux Kustomizations are Ready**

Run:

```bash
kubectl --context understairs -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io calibre-web audiobookshelf
```

Expected: both `READY=True`.

If `Unready`: read the `STATUS` column for the error, then run `flux describe kustomization <name>` for details.

- [ ] **Step 3: Confirm PVCs are Bound**

Run:

```bash
kubectl --context understairs -n calibre-web get pvc
kubectl --context understairs -n audiobookshelf get pvc
```

Expected: `calibre-web-config` Bound; `calibre-web-library` Bound; `audiobookshelf-config` Bound; `audiobookshelf-metadata` Bound; `audiobookshelf-media` Bound.

If any stay `Pending`: `kubectl describe pvc <name>` and check the events. For NFS PVs, the most common failure is `MountVolume.MountDevice failed` with `permission denied` or `connection refused` — verify the Synology export config and that the NAS is reachable from the cluster nodes.

- [ ] **Step 4: Confirm pods are Running**

Run:

```bash
kubectl --context understairs -n calibre-web get pods
kubectl --context understairs -n audiobookshelf get pods
```

Expected: both Deployments have 1/1 Ready.

If pods are `CrashLoopBackOff`: `kubectl logs <pod>` — most likely cause is a permission denied on a mounted volume, indicating UID/GID misalignment on the NAS share.

- [ ] **Step 5: Verify write access to NFS volumes**

Run:

```bash
kubectl --context understairs -n calibre-web exec deploy/calibre-web -- sh -c 'touch /books/.cluster-write-test && ls -la /books/.cluster-write-test && rm /books/.cluster-write-test'
kubectl --context understairs -n audiobookshelf exec deploy/audiobookshelf -- sh -c 'touch /audiobooks/.cluster-write-test && ls -la /audiobooks/.cluster-write-test && rm /audiobooks/.cluster-write-test'
```

Expected: each command shows the file owned by `1027` (or username `k8s-nfs` if `idmapd` is mapping correctly) with group `100` / `users`, then removes it cleanly.

If permission denied: NAS-side `chown k8s-nfs:users <share>` and `chmod g+rwsX <share>` was not applied. Re-run those on the NAS and retry.

- [ ] **Step 6: Verify external reachability**

From the LAN or a Tailscale-connected device:

```bash
curl -I https://books.homelab.blacksd.tech
curl -I https://audiobooks.homelab.blacksd.tech
```

Expected: HTTP 200 (or 302 to a login URL). No certificate errors. No 403 from the SecurityPolicy.

From a non-allowlisted source (e.g., an external machine not on Tailscale): expect 403 from the SecurityPolicy.

- [ ] **Step 7: Confirm Ghostfolio is gone from the live cluster**

Run:

```bash
kubectl --context understairs -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io ghostfolio 2>&1
kubectl --context understairs get namespace ghostfolio 2>&1
```

Expected: `NotFound` for both. If the namespace lingers, check whether Ghostfolio's CNPG Cluster left a finalizer (it can); resolve by deleting the finalizer manually only after confirming the CNPG cluster resource is also gone.

- [ ] **Step 8: Final sanity — point a browser at each app**

Open `https://books.homelab.blacksd.tech` and `https://audiobooks.homelab.blacksd.tech`. Walk through first-time setup for each:
- Calibre-Web: point it at `/books` as the Calibre library location (it expects `metadata.db` there). If the library is empty for now, that's fine — the spec deliberately scoped library *population* out.
- Audiobookshelf: create the admin account, add `/audiobooks` as a library.

If both UIs load and accept their respective library paths, declare done.

---

## Self-Review

**Spec coverage:**

- Goal 1 (Calibre-Web on understairs, NFS-backed, at `books.homelab.blacksd.tech`): Tasks 1–5, 11, 13.
- Goal 2 (Audiobookshelf on understairs, NFS-backed, at `audiobooks.homelab.blacksd.tech`): Tasks 6–10, 12, 13.
- Goal 3 (Remove ghostfolio from cluster Kustomization, keep on disk): Task 13.
- Goal 4 (Install csi-driver-nfs via platform repo): Prereq; handled separately on `feat/csi-driver-nfs-understairs` branch in platform repo.
- Goal 5 (Native Kustomize pattern): Tasks 1–13 follow `apps/<name>/{base,overlays/understairs}` exactly.
- Non-goals (NAS setup, library migration, freeloader deploy, backup, multi-writer support): respected — no tasks for these.
- Storage model (NFS RWX + local RWO config): Tasks 3, 8.
- Identity (1027:100, runAsUser/fsGroup, PUID/PGID, AUDIOBOOKSHELF_UID/GID, UMASK=002): Tasks 1, 6.
- Networking (HTTPRoute + SecurityPolicy, LAN + Tailscale CIDRs): Tasks 4, 9.
- Flux wiring (no SOPS — neither overlay has encrypted secrets): Tasks 11, 12. Correct: neither Flux Kustomization sets `decryption.provider`.
- File inventory (matches the spec): cross-checked, identical paths.
- Integration verification (post-merge): Task 15.

No gaps.

**Placeholder scan:** No "TBD", "TODO", "implement later", "similar to Task N", or hand-waved error handling. Image tags pinned (`lscr.io/linuxserver/calibre-web:0.6.24`, `ghcr.io/advplyr/audiobookshelf:2.16.2`) rather than `:latest`. NAS hostname, paths, UIDs all concrete.

**Type consistency:**

- PVC names referenced in the Deployment match the PVC manifests:
  - Calibre-Web: `calibre-web-config` (Deployment) ↔ `calibre-web-config` (Task 3 step 1). `calibre-web-library` (Deployment) ↔ `calibre-web-library` (Task 3 step 3). PV `calibre-web-library` ↔ PVC `volumeName: calibre-web-library`.
  - Audiobookshelf: `audiobookshelf-config`, `audiobookshelf-metadata`, `audiobookshelf-media` consistent across Deployment and PVC manifests. PV ↔ PVC `volumeName` consistent.
- Service names referenced by HTTPRoute `backendRefs`:
  - Calibre-Web HTTPRoute references service `calibre-web` (port 80) ↔ Service named `calibre-web`, port 80, targetPort `http` (8083). ✓
  - Audiobookshelf HTTPRoute references service `audiobookshelf` (port 80) ↔ Service named `audiobookshelf`, port 80, targetPort `http` (80). ✓
- SecurityPolicy `targetRef` names match the HTTPRoute names in both cases. ✓
- Container port name `http` is used consistently for `targetPort` resolution in both Services. ✓
- Audiobookshelf healthcheck path: `/healthcheck` is the documented endpoint on advplyr/audiobookshelf 2.x. ✓

All consistent. Plan ready.
