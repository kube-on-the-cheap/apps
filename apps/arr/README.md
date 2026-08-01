# arr stack

Media automation stack (Sonarr, Radarr, Prowlarr, Bazarr, ByParr) deployed to the `understairs` cluster in namespace `arr`.

- **Design spec:** `docs/superpowers/specs/2026-07-26-arr-stack-understairs-design.md`
- **External access:** `sonarr|radarr|prowlarr|bazarr.homelab.blacksd.tech`, restricted to LAN (192.168.20.0/24) and Tailscale (100.64.0.0/10)
- **Media root:** NFS `nas.homelab.blacksd.tech:/volume1/Media`, mounted at `/media` in Sonarr/Radarr/Bazarr pods

## Prerequisites (one-time)

On the NAS as an account with sudo:

```bash
sudo mkdir -p /volume1/Media/{downloads/complete,downloads/incomplete,grownups/tv,grownups/movies,kids/tv,kids/movies}
sudo chown -R 1027:100 /volume1/Media
sudo chmod -R 775 /volume1/Media
```

Add an NFS export for `/volume1/Media` covering the understairs cluster CIDR (`rw`, `async`, `no_root_squash`, `insecure`).

## Post-deploy configuration

Everything below is done in the web UIs after Flux reports the stack healthy. None of it can be pre-baked into YAML — the *arr configs live in SQLite under `/config` and the ByParr URL is a UI-only setting in both Prowlarr and Bazarr.

Grab each *arr's API key first from Settings → General → Security → API Key.

### 1. Prowlarr → Apps

Settings → Apps → Add:

- **Sonarr:** Prowlarr Server `http://prowlarr.arr.svc.cluster.local:9696`, Sonarr Server `http://sonarr.arr.svc.cluster.local:8989`, paste Sonarr API key
- **Radarr:** Prowlarr Server `http://prowlarr.arr.svc.cluster.local:9696`, Radarr Server `http://radarr.arr.svc.cluster.local:7878`, paste Radarr API key

Test both. Once green, Prowlarr will push indexer configs to Sonarr/Radarr automatically.

### 2. Prowlarr → FlareSolverr URL

Settings → Indexers → FlareSolverr URL:

```
http://byparr.arr.svc.cluster.local:8191
```

### 3. Sonarr / Radarr → Download Client

In each: Settings → Download Clients → Add → Transmission:

- Host: the LAN IP of the external Transmission host
- Port: Transmission's RPC port (usually 9091)
- URL Base: `/transmission/` (Transmission default)
- Username / Password: the RPC credentials
- Category: `sonarr` in Sonarr, `radarr` in Radarr (optional but keeps queues clean)

Test the connection.

### 4. Sonarr → Root Folders

Settings → Media Management → Root Folders → Add:

- `/media/grownups/tv`
- `/media/kids/tv`

### 5. Radarr → Root Folders

Settings → Media Management → Root Folders → Add:

- `/media/grownups/movies`
- `/media/kids/movies`

### 6. Bazarr → Sonarr / Radarr

Settings → Sonarr:

- Address: `sonarr.arr.svc.cluster.local`
- Port: `8989`
- API key: Sonarr's API key

Settings → Radarr:

- Address: `radarr.arr.svc.cluster.local`
- Port: `7878`
- API key: Radarr's API key

### 7. Bazarr → ByParr

Settings → Subtitles → Anti-Captcha Options → FlareSolverr URL:

```
http://byparr.arr.svc.cluster.local:8191
```

## Auth phase-2 (Authentik) — not yet implemented

To move any of these apps behind Authentik forward-auth later, follow <https://integrations.goauthentik.io/media/sonarr/> and replace the ip-filter `SecurityPolicy` in `apps/arr/overlays/understairs/httproute-<app>.yaml` with an ext-auth `SecurityPolicy` pointing at Authentik. Deployments and Services stay unchanged.
