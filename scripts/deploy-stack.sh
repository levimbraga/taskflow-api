#!/usr/bin/env bash
# Deploy da stack completa usando containers (Docker Compose).
#
# Sobe aplicação em duas réplicas atrás do nginx, mais a pilha de
# observabilidade (Prometheus, Grafana, Loki, Promtail). Ao final valida o
# health check e faz rollback automático se a aplicação não responder.
#
# Uso:
#   ./scripts/deploy-stack.sh                  # usa a imagem :latest do GHCR
#   ./scripts/deploy-stack.sh v1.2.0           # usa uma tag específica
#   ./scripts/deploy-stack.sh --build          # constrói localmente
set -euo pipefail

cd "$(dirname "$0")/.."

REGISTRO="ghcr.io/levimbraga/taskflow-api"
ALVO="${1:-latest}"

if [[ "${ALVO}" == "--build" ]]; then
  export TASKFLOW_IMAGE="taskflow-api:local"
  CONSTRUIR=1
else
  export TASKFLOW_IMAGE="${REGISTRO}:${ALVO}"
  CONSTRUIR=0
fi

echo ">> Imagem alvo: ${TASKFLOW_IMAGE}"

# Guarda a imagem atualmente em execução para permitir rollback.
ANTERIOR=$(docker inspect --format='{{.Config.Image}}' taskflow-app-1 2>/dev/null || echo "")
[[ -n "${ANTERIOR}" ]] && echo ">> Versão atual em execução: ${ANTERIOR}"

if [[ "${CONSTRUIR}" == "1" ]]; then
  echo ">> Construindo a imagem localmente"
  docker compose build app
else
  echo ">> Baixando a imagem do registro"
  docker compose pull app
fi

echo ">> Subindo a stack"
docker compose up -d --remove-orphans

echo ">> Aguardando a aplicação responder ao health check"
for tentativa in $(seq 1 30); do
  if curl -fsS http://localhost/health > /dev/null 2>&1; then
    echo ">> Health check respondeu na tentativa ${tentativa}"
    echo
    curl -sS http://localhost/health; echo
    echo
    echo ">> Serviços em execução:"
    docker compose ps --format "table {{.Service}}\t{{.Status}}"
    echo
    echo ">> Aplicação:  http://localhost"
    echo ">> Grafana:    http://localhost:3000"
    echo ">> Prometheus: http://localhost:9090"
    exit 0
  fi
  sleep 3
done

echo "!! A aplicação não respondeu ao health check" >&2
docker compose logs --tail=50 app nginx >&2

if [[ -n "${ANTERIOR}" ]]; then
  echo ">> Executando rollback para ${ANTERIOR}" >&2
  TASKFLOW_IMAGE="${ANTERIOR}" docker compose up -d app
fi
exit 1
