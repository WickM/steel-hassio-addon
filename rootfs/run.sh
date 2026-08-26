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
: "${PORT:=3000}"
: "${HOST:=0.0.0.0}"
: "${CDP_REDIRECT_PORT:=9223}"
: "${LOG_LEVEL:=warn}"
: "${STEEL_DATA_PATH:=/share/steel}"
: "${CHROME_HEADLESS:=true}"
: "${NODE_ENV:=production}"

export PORT HOST CDP_REDIRECT_PORT LOG_LEVEL STEEL_DATA_PATH CHROME_HEADLESS NODE_ENV

# Ensure data dirs exist (cont-init should have done this already; defensive)
mkdir -p "${STEEL_DATA_PATH}/profiles" "${STEEL_DATA_PATH}/sessions" "${STEEL_DATA_PATH}/logs"

# ---- Launch ----
# Steel's upstream CMD is `node ./api/build/server.js` (or whatever the
# image's CMD is set to). s6-overlay's `run` service execs us, we exec CMD.
# Use bashio::log.blue for visibility in HA log.
if declare -F bashio::log.blue >/dev/null 2>&1; then
    bashio::log.blue "[run.sh] starting steel-browser API on ${HOST}:${PORT}"
    bashio::log.blue "[run.sh] UI: http://<host>:${PORT}/ui"
    bashio::log.blue "[run.sh] CDP: ${HOST}:${CDP_REDIRECT_PORT}"
else
    echo "[run.sh] starting steel-browser API on ${HOST}:${PORT}"
fi

# The upstream CMD is whatever the steel-browser image defines. s6-overlay
# inherits the CMD via its service definition; we exec it directly to keep
# the image's PID 1 behavior (npm/node signal handling intact).
if [ -n "${CMD_OVERRIDE:-}" ]; then
    echo "[run.sh] using CMD_OVERRIDE: ${CMD_OVERRIDE}"
    exec ${CMD_OVERRIDE}
fi

# Fallback: if CMD inheritance somehow broke (rare), fall back to a sane default.
# Steel's image CMD is typically `node ./api/build/server.js`.
if [ -f /app/api/build/server.js ]; then
    echo "[run.sh] exec node /app/api/build/server.js"
    exec node /app/api/build/server.js
fi

# Last resort: run whatever is at $1 or fall back to bash
echo "[run.sh] WARNING: no known steel entrypoint found, falling back to bash"
exec bash
