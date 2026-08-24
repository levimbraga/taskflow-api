#!/usr/bin/env bash
# Build automatizado da imagem de contêiner da aplicação.
# Uso: ./scripts/build.sh [tag]
set -euo pipefail

TAG="${1:-taskflow-api:local}"

echo ">> Construindo imagem ${TAG}"
docker build -t "${TAG}" .

echo ">> Teste de fumaça no contêiner recém-construído"
CONTAINER_ID=$(docker run -d -p 8000:8000 "${TAG}")
trap 'docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true' EXIT

for i in $(seq 1 15); do
  if curl -fsS http://localhost:8000/health >/dev/null 2>&1; then
    echo ">> Health check respondeu com sucesso na tentativa ${i}"
    curl -sS http://localhost:8000/health
    echo
    exit 0
  fi
  sleep 2
done

echo "!! O contêiner não respondeu ao health check" >&2
docker logs "${CONTAINER_ID}" >&2
exit 1
