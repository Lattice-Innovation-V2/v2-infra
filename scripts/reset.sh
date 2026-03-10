#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Resetting v2 infrastructure (destroying data)..."
docker compose down -v
echo "Infrastructure reset. Run ./scripts/start.sh to start fresh."
