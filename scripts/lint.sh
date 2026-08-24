#!/usr/bin/env bash
# Verificação estática de código: estilo, imports e erros comuns.
set -euo pipefail

echo ">> ruff check (lint)"
ruff check .

echo ">> ruff format --check (formatação)"
ruff format --check .

echo ">> Lint concluído com sucesso"
