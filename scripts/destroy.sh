#!/usr/bin/env bash
# Destrói toda a infraestrutura provisionada.
# Execute SEMPRE ao encerrar os testes: o orçamento do Learner Lab é de US$100
# e recursos esquecidos ligados consomem o crédito até a conta ser desativada.
set -euo pipefail

cd "$(dirname "$0")/../infra"
terraform destroy -input=false
