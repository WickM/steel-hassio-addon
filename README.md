# Steel Browser hassio Add-on

Open-source browser API for AI agents, wrapped as a Home Assistant add-on. Apache-2.0.

## What this is

[Steel](https://github.com/steel-dev/steel-browser) is an open-source browser-as-a-service designed for AI agent workloads. This add-on packages the official Steel Docker image with:

- **s6-overlay supervision** — HA can start/stop/restart cleanly
- **bashio integration** — reads addon options from HA's UI
- **Persistent profile storage** at `/share/steel/` — survives container restarts
- **Optional API key + proxy** — lock down the API endpoint if needed
- **Multi-arch** (amd64, aarch64) via the upstream Steel image

## What it's for

Persistent login sessions for AI agents. Use cases:

- **Kaggle** — agent submits to private competitions, no cookie-inject dance
- **Bring!** — login-cookie survives, agent can read your shopping list
- **Notion / GitHub / HelloFresh** — any site with auth that the agent needs

The workflow is: **you log in once manually via the Web UI**, the agent uses the session for weeks until the auth token expires.

## Architecture

```
┌─────────────────────────────────────┐
│ Home Assistant Host                 │
│                                     │
│  ┌──────────────────┐               │
│  │ openclaw         │               │
│  │ (existing)       │               │
│  │                  │               │
│  │ curl/HTTP ───────┼──┐            │
│  └──────────────────┘  │            │
│                        ▼            │
│              ┌────────────────────┐ │
│              │ steel_browser      │ │
│              │ (this addon)       │ │
│              │                    │ │
│              │ Port 3000 (API+UI) │ │
│              │ Port 9223 (CDP)    │ │
│              │ Volume:            │ │
│              │ /share/steel/      │ │
│              │  - profiles/       │ │
│              │  - sessions/       │ │
│              │  - logs/           │ │
│              └────────────────────┘ │
└─────────────────────────────────────┘
```

## Installation (in Home Assistant)

1. **Make the GHCR package public** (only needed once after the first build):
   - Go to https://github.com/WickM/steel-hassio-addon → Packages (right column)
   - Click `steel-hassio-addon` → Settings → Change package visibility → Public
2. **Add this repository to HA**:
   - Settings → Add-ons → Add-on Store → ⋮ → Repositories
   - Paste: `https://github.com/WickM/steel-hassio-addon`
3. **Refresh, install, configure, start**:
   - Click "Steel Browser" in the store → Install
   - Configuration tab: defaults are fine for first try
   - Info tab → Start → wait for "running" → check Log tab
4. **Open the Web UI**:
   - Click "OPEN WEB UI" on the addon's Info tab, or
   - `http://homeassistant.local:3000/ui`
   - First visit: create a session, navigate to e.g. `kaggle.com`, log in manually

## Configuration options

| Option | Default | Purpose |
|--------|---------|---------|
| `steel_port` | 3000 | API + UI port |
| `steel_api_key` | (empty) | Optional — lock down the API |
| `chrome_headless` | true | Set false to render visually (heavier) |
| `chrome_args` | `--no-sandbox,--disable-dev-shm-usage,...` | Chrome CLI flags |
| `log_level` | warn | fatal/error/warn/info/debug/trace |
| `data_path` | /share/steel | Where profiles + sessions live |
| `skip_fingerprint_injection` | false | Disable stealth (only if it breaks a site) |
| `default_timezone` | (empty) | e.g. `Europe/Vienna` for date-aware scraping |
| `proxy_url` | (empty) | `http://user:pass@host:port` |

## How to log in (Manuel workflow)

1. Open `http://homeassistant.local:3000/ui`
2. Click "Create Session"
3. In the session, navigate to e.g. `kaggle.com`
4. **Log in manually** with your credentials + 2FA
5. Steel persists the session state under `/share/steel/profiles/<session-id>/`
6. Next time: just create a session pointing at the same profile — agent is logged in

The agent (OpenClaw) connects via the Steel REST API or via CDP. Sessions persist across addon restarts and HA reboots.

## Anti-bot caveat

**Self-hosted Steel doesn't magically bypass Cloudflare/kaggle bot detection.** That's a Cloud-only feature (residential proxies + CAPTCHA solving). For sites that actively block headless Chrome:

1. Use the cookie-inject pattern (export cookies from your real browser, import into Steel profile) — we already have this for Kaggle
2. Or subscribe to Steel Cloud for residential proxies
3. Or accept that some sites require a CAPTCHA-solving layer (2Captcha etc.) that you add on top

## Development

### Build locally

```bash
cd steel-hassio-addon
docker buildx build --platform linux/amd64 -t steel-hassio-addon:local .
```

### Test the build without HA

```bash
docker run --rm -p 3000:3000 -p 9223:9223 \
    -e PORT=3000 \
    -e NODE_ENV=production \
    -v $(pwd)/test-data:/share/steel \
    steel-hassio-addon:local
# Then http://localhost:3000/ui
```

### Repo layout

```
steel-hassio-addon/
├── Dockerfile              # Wraps ghcr.io/steel-dev/steel-browser with s6
├── config.yaml             # HA schema (options, ports, map)
├── build.yaml              # Multi-arch FROM mapping
├── repository.yaml         # HA add-on store entry
├── info.json               # Repo metadata
├── .github/workflows/      # GH Actions: build → ghcr.io
└── rootfs/
    ├── run.sh              # Main entrypoint, sources env, execs upstream CMD
    └── etc/
        ├── cont-init.d/10-config    # Validates options, prepares /share/steel
        └── services.d/steel/run     # s6 service: re-sources env, execs run.sh
```

## License

Apache-2.0 (inherited from upstream Steel).

## See also

- Steel docs: https://docs.steel.dev
- Steel GitHub: https://github.com/steel-dev/steel-browser
- Companion: `~/clawd/scripts/steel-session.sh` (OpenClaw wrapper for sessions)
- Companion: `brain/deep-plans/2026-08-26-steel-hassio-addon.md` (plan + phases)
