# arr stack — operations reference

Rollout landed via PR #24 (deploy) + follow-up fixes on `main`. This file captures the *live* configuration snapshots taken after we fought through the initial issues, plus the load-bearing platform quirks (Synology DSM 6.2 + NFSv4 + Kubernetes) that shape how the stack has to be operated. Read this before touching Transmission, DSM shares, or the Radarr/Sonarr root folders.

For the deploy checklist and post-install wizard steps, see `README.md`. This file is the *maintenance* companion.

## Snapshot of live config

### Radarr download client

```
name           = Transmission
enabled        = true
host           = nas.homelab.blacksd.tech
port           = 9091
category       = radarr
movieDirectory = (default, uses <download-dir>/<category>)
```

### Radarr Remote Path Mappings

```
host        = nas.homelab.blacksd.tech
remotePath  = /volume1/Media/data/downloads/complete/
localPath   = /media/downloads/complete/
```

Radarr does prefix-match on the mapping. When it queries Transmission and Transmission reports a completed file at `/volume1/Media/data/downloads/complete/radarr/<name>.mkv`, Radarr strips the mapped prefix and joins the remainder to arrive at `/media/downloads/complete/radarr/<name>.mkv` inside the pod. So this single mapping covers both category subdirs and top-level completions.

### Radarr root folders

```
/media/grownups/movies
/media/kids/movies
```

(Sonarr's equivalents: `/media/grownups/tv`, `/media/kids/tv`. Bazarr auto-discovers via Sonarr/Radarr, no roots of its own.)

### Radarr media management (relevant subset)

```
copyUsingHardlinks             = true
skipFreeSpaceCheckWhenImporting = false
minimumFreeSpaceWhenImporting   = 100
importExtraFiles                = false
```

`copyUsingHardlinks` only applies to the automatic download-client → import flow. Manual imports use whatever mode you pick in the wizard (Move / Copy / Hardlink).

### Transmission (on DSM)

```
Runs as user  = sc-transmission (uid 177169)
Runs in group = transmission (gid 190144) + sc-download (65536) + users (100)
download-dir  = /volume1/Media/data/downloads/complete
incomplete-dir = /volume1/Media/data/downloads/incomplete
umask         = 2   (files created 664, dirs 775 — group-writable)
```

The `users` (100) supplementary group is the one that lets Transmission write into directories owned by `k8s-nfs:users`. See "sc-transmission group membership" below for how that was added and how to restore it if DSM strips it.

## Filesystem layout (authoritative)

```
NAS (DSM 6.2):
  /volume1/Media                          (shared folder, DSM-ACL managed, mode 0000+)
    data/                                 (Linux-mode, k8s-nfs:users, 2775)
      downloads/
        complete/                         (k8s-nfs:users 2770)
          radarr/                         (created by Radarr on first grab)
          sonarr/                         (created by Sonarr on first grab)
        incomplete/
      grownups/
        movies/                           (Radarr root folder, .gitkeep sentinel present)
        tv/                               (Sonarr root folder, .gitkeep sentinel present)
      kids/
        movies/                           (Radarr root folder, .gitkeep sentinel present)
        tv/                               (Sonarr root folder, .gitkeep sentinel present)

Pods (mounted view, via nfs.csi.k8s.io):
  /media                                  (= NAS:/volume1/Media/data)
    downloads/complete/…                  (Transmission writes; *arrs read/hardlink)
    grownups/movies/…                     (Radarr writes)
    grownups/tv/…                         (Sonarr writes)
    kids/movies/…
    kids/tv/…
```

Everything the *arrs need lives on a single NFS export. Hardlinks between `downloads/complete/` and `grownups/{tv,movies}` or `kids/{tv,movies}` succeed because the whole tree is a single filesystem from the client's perspective. If any of those paths ever migrate to a different shared folder or a different volume, hardlinks silently degrade to copies.

## DSM 6.2 platform quirks (learned the hard way)

### Shared-folder root NFS mounts don't work

DSM's NFS server exports a shared folder but the mount point at the share root (e.g. `nas:/volume1/Media`) returns ENOENT to clients. Same shared folder mounted one level deep (e.g. `nas:/volume1/Media/data`) works fine. This is a DSM quirk — every working NFS mount in this cluster (`/volume1/Apps/audiobookshelf-media`, `/volume1/Apps/grimmory`) targets a subdirectory. Never point a new PV at a shared-folder root.

### Newly-created shared folders can be poisoned by initial failed mounts

If a client mounts a fresh DSM share while permissions are still wrong, DSM's rmtab and kernel export cache can get into a state where the export appears in `showmount -e` but the kernel refuses to serve it — every mount attempt returns ENOENT and no amount of `exportfs -ra` fixes it. The only reliable escape is deleting the shared folder in DSM UI and recreating it. This bit us on `Media`; if it happens to a future share, don't sink hours into `nfsd`/`rmtab` archaeology — just recreate.

### DSM ACL-managed shares report POSIX mode 0000

Shared folders show `d---------+` in `ls -la` when they're DSM-ACL-managed. The `+` bit means DSM's synoacl decides access, not POSIX. That's fine for NFS clients: idmapd translates the ACL entries into UID/GID grants at mount time, and `k8s-nfs` (uid 1027) inherits the R/W it was granted through the DSM UI. Don't try to `chmod` the shared folder itself to something more permissive — that toggles DSM out of ACL mode entirely and breaks synoacltool, requiring UI re-enable to restore.

### The `crossmnt` NFS export option (Allow subfolder mounts) breaks fresh shares

DSM's UI checkbox "Allow users to access mounted subfolders" sets `crossmnt` on the NFS export. On newly-created shares, this interacts badly with NFSv4 pseudo-root resolution and causes ENOENT for the share root itself.

**Rule:** leave the checkbox OFF while a share is fresh and until every intended cluster mount has succeeded at least once. Subpath mounts still work fine without it — see `pv-media.yaml` which mounts `/volume1/Media/data`, not the share root.

**Safe to enable later on an established share.** Once the share has been mounted successfully and pods are Ready, enabling the checkbox does NOT retroactively break existing mounts (`exportfs -ra` reloads the export table but doesn't unmount live clients). Verified on 2026-08-09 when we enabled it on `Media` to let Kodi mount `/volume1/Media/data/grownups/movies` — all six arr pods stayed 1/1 Running, zero restarts, writes still worked. If you need to enable it for a downstream consumer (Kodi, Plex, another workstation), do it and just watch `kubectl -n arr get pods -w` for a minute afterward.

### DSM NFSv4 identity mapping shows nobody:nobody in pods

Files written on the NAS as `sc-transmission:transmission` show up as `4294967294:4294967294` (nobody) inside the pod's `ls -la`. This is cosmetic — the kernel still compares the raw UIDs on the wire against the pod's UID for POSIX checks, so reads/writes work despite the confusing labels. The reason is idmapd domain mismatch between DSM (`Domain=homelab.blacksd.tech` in `/etc/idmapd.conf`) and the pod's client, which we haven't reconciled. Don't chase this unless something actually breaks.

## sc-transmission group membership

Transmission runs as user `sc-transmission`. It's in `transmission` (its primary GID) and `sc-download` by default. It needs to be added to `users` (GID 100) so it can write to `/volume1/Media/data/downloads/{complete,incomplete}/` (owned `k8s-nfs:users`).

DSM 6.2's `synogroup` binary is buggy and both `--member` and `--add` returned opaque `SYNOLocalAccountGroupSet` errors when trying to add sc-transmission to `users`. `usermod` doesn't exist on DSM. The fix that worked was direct `/etc/group` editing:

```bash
# Current line (empty member list — DSM's synogroup shows this as empty even though users
# is a primary GID for many accounts)
sudo grep "^users:" /etc/group

# Add sc-transmission as a supplementary member
sudo sed -i.bak 's/^users:x:100:$/users:x:100:sc-transmission/' /etc/group

# Verify
id sc-transmission
# Expect: groups=190144(transmission),65536(sc-download),100(users)

# Restart Transmission so the running process picks up the new group
sudo synopkg restart Transmission
```

DSM may re-sync `/etc/group` from its internal user database on package updates or user-UI edits, which would silently strip this. Do NOT touch sc-transmission in DSM Control Panel → User → Edit — that WILL strip `users`. If Transmission starts failing writes to `/volume1/Media/data/downloads/` again, re-check `id sc-transmission` and re-run the sed if needed.

## Radarr / Sonarr root folder failsafe

Radarr and Sonarr refuse to touch monitored items if their configured root folder appears empty (`readdir()` returns nothing). Log message:

```
[Warn] DiskScanService: Movie's root folder (/media/grownups/movies) is empty.
Rescan will not update movies as a failsafe.
```

This is defensive behavior for when NFS silently goes missing — the *arr doesn't want to mark all your movies as "missing" and re-grab them. But it also blocks manual imports when the root is legitimately empty (fresh setup, no movies imported yet).

Workaround: drop a sentinel file in each empty root folder:

```bash
sudo touch /volume1/Media/data/grownups/movies/.gitkeep
sudo touch /volume1/Media/data/grownups/tv/.gitkeep
sudo touch /volume1/Media/data/kids/movies/.gitkeep
sudo touch /volume1/Media/data/kids/tv/.gitkeep
sudo chgrp users /volume1/Media/data/{grownups,kids}/{movies,tv}/.gitkeep
```

Radarr's next scan will see the folder as non-empty and stop the failsafe warnings. Once real movies are imported, the sentinels are optional (safe to leave in place).

## Manual Import UI quirks

Radarr's Manual Import dialog has two panels that behave very differently:

- **"Select Folder" file browser (folder-picker icon)** — shows only directories, hides files. This is a folder chooser, not a file browser. The .mkv you're looking for will NEVER appear here even if it's readable and Radarr's API sees it.
- **The wizard that opens after selecting a folder** — scans the selected folder for movie files, matches them to TMDB entries, and lets you approve import per file.

If you can't see a file in the picker, that's normal — pick the parent folder and the wizard will show the file. To confirm Radarr's backend sees files correctly, hit the API directly:

```bash
API_KEY=$(kubectl -n arr exec deploy/radarr -- grep -oP '(?<=<ApiKey>)[^<]+' /config/config.xml)
kubectl -n arr exec deploy/radarr -- sh -c \
  "wget -qO- --header='X-Api-Key: $API_KEY' \
   'http://localhost:7878/api/v3/manualimport?folder=/media/downloads/complete/&filterExistingFiles=false'" \
  | jq -r '.[] | "\(.path)  →  \(.movie.title // "(no match)")"'
```

## Hardlink verification

Hardlinks are the whole point of importing on the same filesystem — they let both the download client and the *arr library point at the same inode, so importing costs zero extra disk and seeding continues from the same file.

To confirm hardlinks are actually happening after an auto-import:

```bash
kubectl -n arr exec deploy/radarr -- sh -c '
for f in $(find /media/downloads -name "*.mkv" -type f); do
  inode=$(stat -c "%i" "$f")
  match=$(find /media/grownups /media/kids -name "*.mkv" -inum "$inode" 2>/dev/null | head -1)
  if [ -n "$match" ]; then
    echo "HARDLINK ✓  inode=$inode  library=$match"
  else
    echo "COPY (or missing)  inode=$inode  download=$f"
  fi
done
'
```

Same inode number = hardlink succeeded. Different inode = Radarr fell back to copy (both files exist independently, downloads dir uses double the space).

Common reasons hardlinks silently degrade to copies:
- Source and destination are on different filesystems (shouldn't happen with our setup, but if Media/data ever spans mounts, they will)
- `copyUsingHardlinks: false` in Radarr's media management config
- Manual Import wizard was set to Move or Copy (only "Hardlink" mode preserves the source)
- File was moved/deleted before Radarr saw it complete

## Category behavior in Transmission

Vanilla Transmission has no concept of "categories". Radarr fakes it by prefixing the download directory with the category name — completions land in `/volume1/Media/data/downloads/complete/radarr/`, not directly in `complete/`. Sonarr does the same with `.../complete/sonarr/`. When Radarr polls Transmission for its queue, it looks for torrents whose `download-dir` starts with the expected category prefix.

**This means manually-added torrents (added directly in Transmission's UI, not grabbed by Radarr) are INVISIBLE to Radarr's auto-import**, because they lack the category prefix. For those, you have to either move the files to `.../complete/radarr/` and rescan, or use the Manual Import flow.

## Common troubleshooting flow

If Radarr isn't seeing/importing a completed download:

1. **Check the queue via API** — does Radarr even know about it?
   ```bash
   kubectl -n arr exec deploy/radarr -- sh -c \
     "wget -qO- --header='X-Api-Key: <key>' 'http://localhost:7878/api/v3/queue'" | jq
   ```
   Empty = Radarr doesn't see the torrent. Usually means missing category prefix.
2. **Check Radarr's log for the DiskScanService warning** — if the root folder is empty, the failsafe blocks everything.
3. **Confirm the file is readable from the pod:**
   ```bash
   kubectl -n arr exec deploy/radarr -- ls -la /media/downloads/complete/
   ```
   Mode `----------` on a file = it was moved from a DSM-ACL share (Grownups, Kids) and inherited POSIX 0000. Fix: `sudo chmod 664` on the file, `sudo chgrp users`.
4. **Verify Remote Path Mapping** — the API endpoint `/api/v3/remotepathmapping` shows what's active; the host has to exactly match what Radarr uses to talk to Transmission.

## Related files

- `README.md` — deploy checklist and first-run configuration wizard
- `docs/superpowers/specs/2026-07-26-arr-stack-understairs-design.md` — original design spec (local-only per repo gitignore)
- `docs/superpowers/plans/2026-07-31-arr-stack-understairs.md` — implementation plan (local-only)
- `docs/superpowers/specs/dsm-share-compare.sh` (if present) — the diagnostic script that surfaced the DSM ACL / crossmnt / rmtab problems

Also worth reading before touching NFS/DSM:
- `../audiobookshelf/overlays/understairs/pv-media.yaml` — the reference NFS PV pattern
- `../grimmory/README.md` — DSM-side prep documented for that app, same conventions apply here
