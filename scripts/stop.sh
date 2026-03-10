#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Stopping v2 infrastructure..."
docker compose down
echo "Infrastructure stopped."
