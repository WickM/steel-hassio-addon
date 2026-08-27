# Changelog

## 0.1.0 — 2026-08-26

Initial release. Wraps `ghcr.io/steel-dev/steel-browser:latest` with s6-overlay + bashio + persistent `/share/steel` volume.

### Features
- Multi-arch (amd64, aarch64)
- Persistent browser profiles at `/share/steel/profiles/`
- Optional API key + proxy URL via HA config
- Web UI at `http://<host>:3000/ui`
- CDP endpoint at port 9223

### Known limitations
- Self-hosted does NOT include residential proxies (Cloud-only feature)
- CAPTCHA solving not included (Cloud-only)
## 0.1.2 — 2026-08-27

### Fixes
- **CWD bug:** `cd /app` before `exec /app/api/entrypoint.sh`. Steel's entrypoint uses a relative `node ./api/build/index.js` path which fails when s6-overlay inherits CWD=`/run/s6/legacy-services/steel/` (was producing `Cannot find module '/run/s6/legacy-services/steel/api/build/index.js'`).
- **nginx port-bleed cleanup:** defensively kill `nginx.pid` + `fuser -k 9223/tcp` before entrypoint exec. When node crashed, the backgrounded nginx from a previous run kept holding port 9223 with `bind() failed (98: Address already in use)`, blocking s6-overlay restarts.

## 0.1.1 — 2026-08-26

### Fixes
- **Entrypoint detection:** `run.sh` now exec's `/app/api/entrypoint.sh` directly (Steel upstream's real ENTRYPOINT — DBus init + nginx + chromium verification + node), instead of falling through to `exec bash` which caused s6 to loop forever on exit 0. Fallback chain: `entrypoint.sh` → `node ./api/build/index.js` → `exit 1` (no more silent `exec bash`).

## 0.1.0 — 2026-08-26

Initial release. Wraps `ghcr.io/steel-dev/steel-browser:latest` with s6-overlay + bashio + persistent `/share/steel` volume.

### Features
- Multi-arch (amd64, aarch64)
- Persistent browser profiles at `/share/steel/profiles/`
- Optional API key + proxy URL via HA config
- Web UI at `http://<host>:3000/ui`
- CDP endpoint at port 9223
- `host_url` option so Steel UI links resolve correctly behind reverse proxies (added in 1679387)

### Known limitations
- Self-hosted does NOT include residential proxies (Cloud-only feature)
- CAPTCHA solving not included (Cloud-only)
- Multi-arch matrix currently amd64 only (HA host is amd64); aarch64 support deferred
