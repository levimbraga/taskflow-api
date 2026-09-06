#!/usr/bin/env bash
# Varredura de segurança executada localmente e no pipeline.
#
#   1. pip-audit  - vulnerabilidades conhecidas nas dependências Python
#   2. Trivy      - vulnerabilidades no sistema de arquivos da imagem
#   3. Gitleaks   - segredos acidentalmente versionados
#
# Uso: ./scripts/security-scan.sh [imagem]
set -euo pipefail

cd "$(dirname "$0")/.."
IMAGEM="${1:-taskflow-api:local}"
FALHAS=0

echo ">> [1/3] pip-audit: dependências Python"
if command -v pip-audit >/dev/null 2>&1; then
  pip-audit --requirement requirements.txt --strict || FALHAS=1
else
  echo "   pip-audit não instalado; execute: pip install pip-audit"
fi

echo
echo ">> [2/3] Trivy: imagem de contêiner"
if command -v trivy >/dev/null 2>&1; then
  trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed "${IMAGEM}" || FALHAS=1
else
  echo "   Trivy não instalado localmente; a varredura roda no pipeline de CI"
fi

echo
echo ">> [3/3] Gitleaks: segredos no repositório"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --no-banner --redact || FALHAS=1
else
  echo "   Gitleaks não instalado localmente; a varredura roda no pipeline de CI"
fi

echo
if [[ "${FALHAS}" == "0" ]]; then
  echo ">> Nenhum problema de segurança bloqueante encontrado"
else
  echo "!! Foram encontrados problemas de segurança" >&2
  exit 1
fi
