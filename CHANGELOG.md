# Changelog

## 0.1.11 — 2026-08-28

### Fixes
- **Container restart loop with `EADDRNOTAVAIL: address not available 172.30.32.1:3000`:** v0.1.10's hardcoded `HOST=172.30.32.1` was wrong — that's the **openclaw Companion IP**, not the Steel-addon's own IP. From inside the Steel container, `172.30.32.1` is a remote address on a different container's network namespace; Node's `listen()` rejects it with `EADDRNOTAVAIL` because the local interface has no such IP, then s6-overlay restarts the service, which kills any stale nginx (defensive cleanup), then crashes again → tight crash loop. Fix: `10-config` now auto-detects the Steel container's own IP via `hostname -I | awk '{print $1}'` and exports that as the `HOST` fallback when `host_url` is empty. Last-resort fallback (only if `hostname -I` yields nothing) is still `0.0.0.0` with a loud WARNING so it doesn't silently break the UI again.

### Lesson (MEMORY.md)
- **Never hardcode another container's IP as this container's `HOST`/`bind` address.** `172.30.32.1` is the Supervisor bridge IP that openclaw (a Companion) lives at; Steel (a real addon) gets a different IP per container restart on `172.30.32.0/23` (e.g. `172.30.33.12`). Always use `hostname -I` for the container's own IP, or `0.0.0.0` to bind-all.

## 0.1.10 — 2026-08-28

### Fixes
- **UI unusable (Swagger/UI still showed 0.0.0.0 in v0.1.8/v0.1.9):** The earlier "leave HOST unset if host_url is empty" logic in `10-config` was wrong: Steel's own default for `HOST` is `"0.0.0.0"` (see `api/src/env.ts` in steel-browser repo), and Steel embeds that value verbatim into every self-generated URL (Swagger `Server` field, session `debugUrl`/`websocketUrl`/`sessionViewerUrl`, `devtoolsInspectorUrl`). Leaving `HOST` unset is **strictly worse** than setting it to `172.30.32.1` because Steel falls back to `0.0.0.0`, which makes the UI/Swagger unreachable from a real browser. `10-config` now ALWAYS exports `HOST` — either from `host_url` if set in HA Configuration, or from the hardcoded fallback (`172.30.32.1`, the Supervisor bridge IP). The `/tmp/.steel-env` file (sourced by `run.sh` via `set -a`) now also unconditionally writes `export HOST='...'`. Override the default in HA Configuration → host_url if your setup uses a different external IP/hostname.

## 0.1.9 — 2026-08-28

### Fixes
- **Container crash (`/run.sh: line 97: HOST: unbound variable`):** Line 97 of `rootfs/run.sh` referenced `${HOST}` without a default, which crashes under `set -u` (active because bashio's shebang enables it). Fixed by using `${HOST:-}` consistently — the conditional export on line 76 already used it correctly, but the late display-host check on line 97 didn't. One-character fix, completes the v0.1.5/v0.1.6 `set +eu` work — that fix let the script start, but this line still tripped on `set -u` later.

## 0.1.8 — 2026-08-28

### Fixes
- **UI unusable (Swagger/UI still shows 0.0.0.0):** When `host_url` is empty in HA config, `10-config` now falls back to the supervisor-bridge IP (`172.30.32.1`) instead of leaving HOST unset. With this fallback, Steel's API serves Swagger/UI at the actual reachable address rather than `0.0.0.0`, which browsers can't resolve. Note: this change did NOT fix the actual line-97 crash reported in HA logs — that fix lands in 0.1.9.

## 0.1.7 — 2026-08-28

### Fixes
- **UI unusable (HOST=0.0.0.0 in embedded links):** `10-config` now actively detects the container's IP at startup (via `hostname -I` or by deriving from `host_url` in HA config) and exports it as `HOST` before Steel's Node process starts. This complements the v0.1.6 removal of the `HOST=0.0.0.0` defensive default — without a real value to export, Steel's own `HOST ?? "0.0.0.0"` default still won. Note: this change did NOT fix the actual line-97 crash reported in HA logs — that fix lands in 0.1.9.

## 0.1.6 — 2026-08-28

### Fixes
- **UI/Swagger host fixed:** `HOST=0.0.0.0` no longer appears in generated UI/Swagger URLs. Steel's own default `HOST=0.0.0.0` is now overridden at runtime by auto-detecting the container's real IP or by passing `host_url` from HA config. `10-config` now sources `/tmp/.steel-env` explicitly and exports `HOST` before Steel's Node process starts. The OPTIONS_FILE unbound-variable crash was also fixed so the config script actually reaches the export stage.
- **Container crash (`OPTIONS_FILE: unbound variable`):** `rootfs/etc/cont-init.d/10-config` now starts with `set +eu` (not just `set +e`) immediately after the `#!/usr/bin/bashio` shebang. Bashio internally enables `set -u` (nounset) on load, and `set +e` alone only disables `-e`, not `-u`. Re-enabled `set -e` at script end so future fatal misconfig still fails the container instead of silently starting with defaults.
- **UI unusable (HOST=0.0.0.0 in embedded links):** Removed `: "${HOST:=0.0.0.0}"` defensive default from `rootfs/run.sh`. When `host_url` is empty in HA config, Steel now auto-detects the host from `req.hostname` of the incoming HTTP request (instead of embedding `0.0.0.0` into every self-generated UI link — session URLs, devtoolsInspectorUrl, debugUrl, recording player). HOST export is now conditional (`if [ -n "${HOST:-}" ]; then export HOST; fi`), and the startup log prints `<auto-detect-from-request>` when HOST is empty so the active mode is obvious in HA logs.

## 0.1.5 — 2026-08-28

### Fixes
- **Container crash (`OPTIONS_FILE: unbound variable`):** `rootfs/etc/cont-init.d/10-config` now starts with `set +eu` (not just `set +e`) immediately after the `#!/usr/bin/bashio` shebang. Bashio internally enables `set -u` (nounset) on load, and `set +e` alone only disables `-e`, not `-u`. Re-enabled `set -e` at script end so future fatal misconfig still fails the container instead of silently starting with defaults.
- **UI unusable (HOST=0.0.0.0 in embedded links):** Removed `: "${HOST:=0.0.0.0}"` defensive default from `rootfs/run.sh`. When `host_url` is empty in HA config, Steel now auto-detects the host from `req.hostname` of the incoming HTTP request (instead of embedding `0.0.0.0` into every self-generated UI link — session URLs, devtoolsInspectorUrl, debugUrl, recording player). HOST export is now conditional (`if [ -n "${HOST:-}" ]; then export HOST; fi`), and the startup log prints `<auto-detect-from-request>` when HOST is empty so the active mode is obvious in HA logs.

## 0.1.2 — 2026-08-27

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
