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
- v0.1.0: relies on upstream CMD inheritance — verify `/app/api/build/server.js` path after first build; fall back to `CMD_OVERRIDE` env var if upstream changes layout
