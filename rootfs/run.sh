#!/usr/bin/env bashio
# Steel Browser API server entrypoint.
# Reads options from /data/options.json, exports them as env vars for Steel's
# Node process, then execs the upstream `steel` entrypoint.
#
# Steel's official image runs `node ./api/build/server.js` (or similar) via
# its own CMD. We don't replace that — we just inject HA options into env
# before exec'ing whatever CMD the upstream image set. s6-overlay lets us
# override the final CMD via /etc/services.d/steel/run, which calls this
# script, which then `exec`s the upstream command.
#
# The cont-init.d/10-config script is responsible for:
#   - preparing /share/steel persistent dirs
#   - exporting all options as env vars (so they're available here)
set -e

# Steel's upstream image starts its node process directly. We exec whatever
# CMD the image shipped with, but first inject our env.
# Source the cont-init exports if not already inherited:
if [ -f /tmp/.steel-env ]; then
    set -a
    . /tmp/.steel-env
    set +a
fi

# ---- Diagnostics ----
echo "[run.sh] uid=$(id -u) cwd=$(pwd) PATH=$PATH"
echo "[run.sh] node: $(command -v node || echo 'NOT FOUND')"
echo "[run.sh] PORT=${PORT:-3000} HOST=${HOST:-0.0.0.0}"
echo "[run.sh] STEEL_DATA_PATH=${STEEL_DATA_PATH:-/share/steel}"
echo "[run.sh] CHROME_HEADLESS=${CHROME_HEADLESS:-true}"
echo "[run.sh] CHROME_ARGS=${CHROME_ARGS:-<unset>}"
echo "[run.sh] CDP_REDIRECT_PORT=${CDP_REDIRECT_PORT:-9223}"
echo "[run.sh] LOG_LEVEL=${LOG_LEVEL:-warn}"
echo "[run.sh] PROXY_URL=${PROXY_URL:-<unset>}"
echo "[run.sh] SKIP_FINGERPRINT_INJECTION=${SKIP_FINGERPRINT_INJECTION:-false}"
echo "[run.sh] DEFAULT_TIMEZONE=${DEFAULT_TIMEZONE:-<unset>}"

# ---- Defensive defaults ----
# NOTE: do NOT default HOST to anything (especially not 0.0.0.0). When
# Steel embeds "0.0.0.0:3000" in self-generated UI/CDP URLs, the web UI
# becomes unreachable from a real browser. If host_url is empty in the
# HA config, Steel's own code falls back to req.hostname from the
# incoming HTTP request, which is what we want. So we only default HOST
# here if the user actually set it via host_url — otherwise leave it
# unset and let Steel's auto-detect kick in.
: "${PORT:=3000}"
: "${CDP_REDIRECT_PORT:=9223}"
: "${LOG_LEVEL:=warn}"
: "${STEEL_DATA_PATH:=/share/steel}"
: "${CHROME_HEADLESS:=true}"
: "${NODE_ENV:=production}"

# Export only what we set. HOST is intentionally conditional — if
# /tmp/.steel-env didn't define it (because host_url was empty), we
# leave it unset so Steel can detect from req.hostname.
export PORT CDP_REDIRECT_PORT LOG_LEVEL STEEL_DATA_PATH CHROME_HEADLESS NODE_ENV
if [ -n "${HOST:-}" ]; then
    export HOST
fi

# Ensure data dirs exist (cont-init should have done this already; defensive)
mkdir -p "${STEEL_DATA_PATH}/profiles" "${STEEL_DATA_PATH}/sessions" "${STEEL_DATA_PATH}/logs"

# ---- Steel upstream cwd ----
# Steel's upstream image sets WORKDIR=/app and its entrypoint.sh runs
# `exec node ./api/build/index.js` with a RELATIVE path. s6-overlay's
# legacy-service runs us with CWD=/run/s6/legacy-services/steel/, so
# node would fail with "Cannot find module '/run/s6/.../api/build/index.js'".
# Fix: cd to /app before exec'ing the upstream entrypoint.
cd /app

# ---- Defensive nginx cleanup ----
# Steel's entrypoint.sh starts nginx in the background before launching node.
# If node crashes (wrong cwd, missing dep), entrypoint exits but nginx keeps
# running on port 9223. Next s6 restart then fails with
# `bind() to 0.0.0.0:9223 failed (98: Address already in use)`.
# Kill any leftover nginx master so the fresh entrypoint can bind cleanly.
if [ -f /var/run/nginx.pid ]; then
    echo "[run.sh] defensive: killing stale nginx (pid=$(cat /var/run/nginx.pid))"
    kill "$(cat /var/run/nginx.pid)" 2>/dev/null || true
    sleep 1
    rm -f /var/run/nginx.pid
fi
# Also nuke anything else still holding 9223 (paranoid).
if command -v fuser >/dev/null 2>&1; then
    fuser -k 9223/tcp 2>/dev/null || true
fi

# ---- Launch ----
# Steel's upstream CMD is `node ./api/build/server.js` (or whatever the
# image's CMD is set to). s6-overlay's `run` service execs us, we exec CMD.
# Use bashio::log.blue for visibility in HA log.
# Display host as <auto> when not explicitly set, so logs make clear
# Steel will auto-detect from req.hostname.
_DISPLAY_HOST="${HOST:-<auto-detect-from-request>}"
if [ -n "${HOST}" ]; then
    _DISPLAY_HOST="${HOST}"
fi
if declare -F bashio::log.blue >/dev/null 2>&1; then
    bashio::log.blue "[run.sh] starting steel-browser API on ${_DISPLAY_HOST}:${PORT}"
    bashio::log.blue "[run.sh] UI: http://<host>:${PORT}/ui"
    bashio::log.blue "[run.sh] CDP: ${_DISPLAY_HOST}:${CDP_REDIRECT_PORT}"
else
    echo "[run.sh] starting steel-browser API on ${_DISPLAY_HOST}:${PORT}"
fi

# The upstream CMD is whatever the steel-browser image defines. s6-overlay
# inherits the CMD via its service definition; we exec it directly to keep
# the image's PID 1 behavior (npm/node signal handling intact).
if [ -n "${CMD_OVERRIDE:-}" ]; then
    echo "[run.sh] using CMD_OVERRIDE: ${CMD_OVERRIDE}"
    exec ${CMD_OVERRIDE}
fi

# Fallback: if CMD inheritance somehow broke (rare), exec Steel's actual
# upstream entrypoint. Per steel-dev/steel-browser Dockerfile (2026-08):
#   ENTRYPOINT ["/app/api/entrypoint.sh"]
# which in turn runs `exec node ./api/build/index.js`. The entrypoint.sh
# handles DBus init, nginx (optional), Chrome verification, then starts
# the node process — so we want to call IT, not bypass it.
if [ -x /app/api/entrypoint.sh ]; then
    echo "[run.sh] exec /app/api/entrypoint.sh (steel upstream entrypoint)"
    exec /app/api/entrypoint.sh
fi

# Last resort: try the actual node server file (steel-browser 2026-08
# layout: /app/api/build/index.js, NOT server.js as I initially assumed)
if [ -f /app/api/build/index.js ]; then
    echo "[run.sh] exec node /app/api/build/index.js"
    exec node /app/api/build/index.js
fi

# Truly nothing matched — log loudly and exit so s6-overlay marks us failed
# (better than silently falling back to bash which would loop forever).
echo "[run.sh] FATAL: no known steel entrypoint found"
echo "[run.sh] /app/api/entrypoint.sh exists? $(test -x /app/api/entrypoint.sh && echo yes || echo no)"
echo "[run.sh] /app/api/build/index.js exists? $(test -f /app/api/build/index.js && echo yes || echo no)"
echo "[run.sh] /app/api/build contents:"
ls -la /app/api/build/ 2>/dev/null || echo "  (cannot list /app/api/build)"
exit 1
