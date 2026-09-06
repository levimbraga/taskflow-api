#!/usr/bin/env bash
# Deploy da stack completa usando containers (Docker Compose).
#
# Sobe aplicação em duas réplicas atrás do nginx, mais a pilha de
# observabilidade (Prometheus, Grafana, Loki, Promtail). Ao final valida o
# health check e faz rollback automático se a aplicação não responder.
#
# Uso:
#   ./scripts/deploy-stack.sh                        # usa a imagem :latest do GHCR
#   ./scripts/deploy-stack.sh 2026.09.06-a1b2c3d     # usa uma tag específica
#   ./scripts/deploy-stack.sh --build                # constrói localmente
#   ./scripts/deploy-stack.sh taskflow-api:teste     # usa uma referência inteira
set -euo pipefail

cd "$(dirname "$0")/.."

REGISTRO="ghcr.io/levimbraga/taskflow-api"
ALVO="${1:-latest}"

CONSTRUIR=0
if [[ "${ALVO}" == "--build" ]]; then
  export TASKFLOW_IMAGE="taskflow-api:local"
  CONSTRUIR=1
elif [[ "${ALVO}" == *[:/@]* ]]; then
  # Referência completa (inclusive por digest), útil para reimplantar uma versão
  # específica ou para validar o caminho de rollback.
  export TASKFLOW_IMAGE="${ALVO}"
else
  export TASKFLOW_IMAGE="${REGISTRO}:${ALVO}"
fi

echo ">> Imagem alvo: ${TASKFLOW_IMAGE}"

# Guarda a imagem atualmente em execução para permitir rollback.
#
# É gravado o ID da imagem (sha256:...) e não o nome da tag: como a implantação
# normal usa sempre :latest, guardar o nome faria o "rollback" reapontar para a
# mesma imagem quebrada que acabou de subir. O ID identifica o binário exato que
# estava no ar e continua resolvível localmente mesmo depois de a tag ter sido
# movida no registro.
ANTERIOR=$(docker inspect --format='{{.Image}}' taskflow-app-1 2>/dev/null || echo "")
if [[ -n "${ANTERIOR}" ]]; then
  ROTULO_ANTERIOR=$(docker inspect --format='{{.Config.Image}}' taskflow-app-1 2>/dev/null || echo "?")
  echo ">> Versão atual em execução: ${ROTULO_ANTERIOR} (${ANTERIOR:0:19})"
fi

if [[ "${CONSTRUIR}" == "1" ]]; then
  echo ">> Construindo a imagem localmente"
  docker compose build app
elif [[ "${TASKFLOW_IMAGE}" == "${REGISTRO}:"* ]]; then
  echo ">> Baixando a imagem do registro"
  docker compose pull app
else
  echo ">> Usando a imagem informada, sem baixar do registro"
fi

echo ">> Subindo a stack"
# --force-recreate no app: sem isso, uma tag móvel como :latest que mudou de
# digest poderia deixar o contêiner antigo de pé por já "existir".
docker compose up -d --remove-orphans --no-build
docker compose up -d --no-build --force-recreate app

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

if [[ -z "${ANTERIOR}" ]]; then
  echo "!! Nao havia versao anterior em execucao; nada a reverter" >&2
  exit 1
fi

echo ">> Executando rollback para ${ROTULO_ANTERIOR} (${ANTERIOR:0:19})" >&2
TASKFLOW_IMAGE="${ANTERIOR}" docker compose up -d --no-build --force-recreate app

for tentativa in $(seq 1 20); do
  if curl -fsS http://localhost/health > /dev/null 2>&1; then
    echo ">> Rollback concluido: a versao anterior respondeu na tentativa ${tentativa}" >&2
    exit 1
  fi
  sleep 3
done

echo "!! O rollback tambem nao respondeu ao health check" >&2
exit 1
