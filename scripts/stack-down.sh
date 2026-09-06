#!/usr/bin/env bash
# Derruba a stack de containers. Use --volumes para apagar também os dados
# persistidos do Prometheus, Loki e Grafana.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--volumes" ]]; then
  docker compose down --volumes --remove-orphans
  echo ">> Stack removida, incluindo os volumes de dados"
else
  docker compose down --remove-orphans
  echo ">> Stack removida (volumes preservados)"
fi
