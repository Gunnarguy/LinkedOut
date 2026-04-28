#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_HOST="${LINKEDOUT_PI_HOST:-gunzino}"
REMOTE_DIR="${LINKEDOUT_PI_DIR:-linkedout}"
SYNC_ENV=0
SYNC_DATA=0

export COPYFILE_DISABLE=1

usage() {
    cat <<'EOF'
Usage: ./deploy-to-pi.sh [--host HOST] [--sync-env] [--sync-data]

Options:
  --host HOST    Tailscale hostname of the Raspberry Pi (default: gunzino)
  --sync-env     Overwrite the Pi backend/.env with the local backend/.env
  --sync-data    Overwrite the Pi data/ directory with the local data/
  --help         Show this help text

Behavior:
  - Syncs backend/ and docker-compose.yml to ~/linkedout on the Pi
  - Preserves the Pi's backend/.env and data/ by default
  - Seeds backend/.env and data/ automatically if the Pi copy does not exist yet
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            PI_HOST="$2"
            shift 2
            ;;
        --sync-env)
            SYNC_ENV=1
            shift
            ;;
        --sync-data)
            SYNC_DATA=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

for cmd in tailscale python3 curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd"
        exit 1
    fi
done

LOCAL_ENV="$PROJECT_DIR/backend/.env"
if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Missing backend/.env. Copy backend/.env.example to backend/.env first."
    exit 1
fi

echo "Checking Tailscale SSH access to $PI_HOST..."
tailscale ssh "$PI_HOST" "echo ok" >/dev/null

echo "Resolving Pi MagicDNS hostname..."
PI_DNS="$(tailscale ssh "$PI_HOST" "python3 -c 'import json,subprocess; print(json.loads(subprocess.check_output([\"tailscale\", \"status\", \"--json\"]))[\"Self\"][\"DNSName\"].rstrip(\".\"))'")"
if [[ -z "$PI_DNS" ]]; then
    echo "Could not determine the Pi MagicDNS hostname."
    exit 1
fi

echo "Preparing remote directory ~/$(printf '%s' "$REMOTE_DIR")..."
tailscale ssh "$PI_HOST" "mkdir -p ~/$REMOTE_DIR/backend ~/$REMOTE_DIR/data"

REMOTE_ENV_PRESENT="$(tailscale ssh "$PI_HOST" "test -f ~/$REMOTE_DIR/backend/.env && echo yes || echo no")"
REMOTE_DATA_PRESENT="$(tailscale ssh "$PI_HOST" "if [ -f ~/$REMOTE_DIR/data/job_store.json ] || [ -f ~/$REMOTE_DIR/data/sessions.json ]; then echo yes; else echo no; fi")"

echo "Syncing backend code..."
cd "$PROJECT_DIR"
tar \
    --no-mac-metadata \
    --exclude='./backend/.env' \
    --exclude='./backend/__pycache__' \
    --exclude='./backend/*.pyc' \
    --exclude='./__pycache__' \
    --exclude='./.pytest_cache' \
    -cf - docker-compose.yml backend | tailscale ssh "$PI_HOST" "cd ~/$REMOTE_DIR && tar -xf -"

if (( SYNC_ENV )) || [[ "$REMOTE_ENV_PRESENT" == "no" ]]; then
    echo "Syncing backend/.env..."
    tailscale ssh "$PI_HOST" "cat > ~/$REMOTE_DIR/backend/.env" < "$LOCAL_ENV"
else
    echo "Preserving remote backend/.env"
fi

if (( SYNC_DATA )) || [[ "$REMOTE_DATA_PRESENT" == "no" ]]; then
    echo "Syncing data/ ..."
    tar --no-mac-metadata -cf - data | tailscale ssh "$PI_HOST" "cd ~/$REMOTE_DIR && tar -xf -"
else
    echo "Preserving remote data/"
fi

echo "Building and starting LinkedOut on the Pi..."
tailscale ssh "$PI_HOST" "cd ~/$REMOTE_DIR && docker compose up --build -d"

echo "Verifying backend health on the Pi..."
tailscale ssh "$PI_HOST" "curl -fsS --retry 10 --retry-delay 1 --retry-all-errors --retry-connrefused http://127.0.0.1:8443/health >/dev/null"

echo "Verifying backend health over Tailscale..."
HEALTH_JSON="$(curl -fsS --retry 10 --retry-delay 1 --retry-all-errors --retry-connrefused "http://$PI_DNS:8443/health")"

echo "LinkedOut backend is live on the Raspberry Pi"
echo "Pi URL: http://$PI_DNS:8443"
echo "Health: $HEALTH_JSON"
echo "Clients need Tailscale enabled to reach the Pi backend directly."
