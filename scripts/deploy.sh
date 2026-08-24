#!/usr/bin/env bash
# Provisiona a infraestrutura na AWS via Terraform.
#
# Pré-requisito: exportar as credenciais da sessão do AWS Academy Learner Lab
# (AWS Details > AWS CLI) antes de executar. Elas expiram junto com a sessão
# do laboratório e precisam ser atualizadas a cada novo Start Lab.
set -euo pipefail

: "${AWS_ACCESS_KEY_ID:?Exporte as credenciais do Learner Lab antes de continuar}"
: "${AWS_SECRET_ACCESS_KEY:?Exporte as credenciais do Learner Lab antes de continuar}"
: "${AWS_SESSION_TOKEN:?Exporte as credenciais do Learner Lab antes de continuar}"

cd "$(dirname "$0")/../infra"

echo ">> terraform init"
terraform init -input=false

echo ">> terraform fmt -check"
terraform fmt -check -recursive

echo ">> terraform validate"
terraform validate

echo ">> terraform plan"
terraform plan -input=false -out=tfplan

read -rp "Aplicar este plano? (digite 'sim' para confirmar): " RESPOSTA
if [[ "${RESPOSTA}" != "sim" ]]; then
  echo ">> Aplicação cancelada pelo usuário"
  exit 0
fi

echo ">> terraform apply"
terraform apply -input=false tfplan

echo
echo ">> Infraestrutura provisionada. Endpoints:"
terraform output
