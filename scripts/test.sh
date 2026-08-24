#!/usr/bin/env bash
# Executa a suíte automatizada de testes com relatório de cobertura.
# Falha se a cobertura ficar abaixo do mínimo definido em pyproject.toml (90%).
set -euo pipefail

echo ">> Executando testes unitários e de integração"
python -m pytest

echo ">> Testes concluídos com sucesso"
