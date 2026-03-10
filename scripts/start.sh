#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Starting v2 infrastructure..."
docker compose up -d
echo "Waiting for PostgreSQL..."
until docker compose exec postgres pg_isready -U postgres -d lattice_v2 2>/dev/null; do
  sleep 1
done
echo "Waiting for Redis..."
until docker compose exec redis redis-cli ping 2>/dev/null | grep -q PONG; do
  sleep 1
done
echo "Infrastructure ready!"
echo "  PostgreSQL: localhost:5434 (lattice_v2)"
echo "  Redis:      localhost:6380"
