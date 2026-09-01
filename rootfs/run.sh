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
echo "[run.sh] PORT=${PORT:-3000} HOST=${HOST:-<unset>}"
echo "[run.sh] DOMAIN=${DOMAIN:-<unset — Steel falls back to HOST in URLs>}"
echo "[run.sh] CDP_DOMAIN=${CDP_DOMAIN:-<unset — Steel falls back to HOST:CDP_REDIRECT_PORT in URLs>}"
echo "[run.sh] STEEL_DATA_PATH=${STEEL_DATA_PATH:-/share/steel}"
echo "[run.sh] CHROME_HEADLESS=${CHROME_HEADLESS:-true}"
echo "[run.sh] CHROME_ARGS=${CHROME_ARGS:-<unset>}"
echo "[run.sh] CDP_REDIRECT_PORT=${CDP_REDIRECT_PORT:-9223}"
echo "[run.sh] LOG_LEVEL=${LOG_LEVEL:-warn}"
echo "[run.sh] PROXY_URL=${PROXY_URL:-<unset>}"
echo "[run.sh] SKIP_FINGERPRINT_INJECTION=${SKIP_FINGERPRINT_INJECTION:-false}"
echo "[run.sh] DEFAULT_TIMEZONE=${DEFAULT_TIMEZONE:-<unset>}"

# ---- Defensive defaults ----
# v0.1.15: HOST is the bind address (10-config sets 0.0.0.0). DOMAIN is
# the URL host (10-config sets from `host_url` HA option, may be unset).
# We don't default HOST here — 10-config already set it. We only default
# PORT/CDP_REDIRECT_PORT/etc. in case /tmp/.steel-env didn't define them
# (shouldn't happen, defensive).
: "${PORT:=3000}"
: "${CDP_REDIRECT_PORT:=9223}"
: "${LOG_LEVEL:=warn}"
: "${STEEL_DATA_PATH:=/share/steel}"
: "${CHROME_HEADLESS:=true}"
: "${NODE_ENV:=production}"

# Export the resolved values. HOST must always be set (10-config sets
# 0.0.0.0). DOMAIN/CDP_DOMAIN are conditional — leave unset if user
# didn't configure host_url in HA Configuration.
export PORT CDP_REDIRECT_PORT LOG_LEVEL STEEL_DATA_PATH CHROME_HEADLESS NODE_ENV
export HOST
if [ -n "${DOMAIN:-}" ]; then
    export DOMAIN
fi
if [ -n "${CDP_DOMAIN:-}" ]; then
    export CDP_DOMAIN
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
# Display host for log lines. v0.1.15: HOST is the bind address (always
# 0.0.0.0), DOMAIN is the URL host (from host_url HA option). For log
# display we want the URL the user actually opens in their browser —
# so prefer DOMAIN, fall back to HOST for display only. This is purely
# cosmetic; the actual listen address is HOST=0.0.0.0.
_DISPLAY_HOST="${DOMAIN:-${HOST:-0.0.0.0}}"
# Defensive strip scheme (shouldn't happen — 10-config normalizes)
case "${_DISPLAY_HOST}" in
    http://*|https://*)
        _DISPLAY_HOST="${_DISPLAY_HOST#http://}"
        _DISPLAY_HOST="${_DISPLAY_HOST#https://}"
        ;;
esac
# Defensive strip trailing :PORT (avoid http://1.2.3.4:3000:3000 in logs)
case "${_DISPLAY_HOST}" in
    *":${PORT}")
        _DISPLAY_HOST="${_DISPLAY_HOST%:${PORT}}"
        ;;
esac
if declare -F bashio::log.blue >/dev/null 2>&1; then
    bashio::log.blue "[run.sh] starting steel-browser API on http://${_DISPLAY_HOST}:${PORT}"
    bashio::log.blue "[run.sh] UI:    http://${_DISPLAY_HOST}:${PORT}/ui"
    bashio::log.blue "[run.sh] CDP:   http://${_DISPLAY_HOST}:${CDP_REDIRECT_PORT}"
    if [ "${HOST}" != "0.0.0.0" ]; then
        bashio::log.blue "[run.sh] note: HOST=${HOST} (bind address, separate from DOMAIN)"
    fi
else
    echo "[run.sh] starting steel-browser API on http://${_DISPLAY_HOST}:${PORT}"
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
