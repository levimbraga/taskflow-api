# TaskFlow API — DevOps na Prática (PUCRS)

Entrega da **Fase 1 — Configuração e Automação Inicial**: pipeline de integração
contínua, testes automatizados e infraestrutura como código para uma API REST em
Python.

![CI](https://github.com/levimbraga/taskflow-api/actions/workflows/ci.yml/badge.svg)

---

## 1. Sobre o projeto

A **TaskFlow API** é uma API REST de gerenciamento de tarefas construída com
FastAPI. A aplicação é propositalmente enxuta: o objeto de estudo desta
disciplina é a *esteira* que leva o código do commit até a nuvem, não a regra de
negócio. Ainda assim, a API é funcional e coberta por testes, o que a torna um
alvo realista para o pipeline.

### Endpoints

| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/health` | Health check consumido pelo Docker e pelo teste de fumaça pós-deploy |
| `GET` | `/tasks` | Lista tarefas, com filtro opcional `?completed=true` ou `?completed=false` |
| `GET` | `/tasks/{id}` | Detalha uma tarefa |
| `POST` | `/tasks` | Cria uma tarefa |
| `PATCH` | `/tasks/{id}` | Atualização parcial |
| `DELETE` | `/tasks/{id}` | Remove uma tarefa |
| `GET` | `/docs` | Documentação interativa (Swagger UI) |

---

## 2. Como executar localmente

```bash
git clone https://github.com/levimbraga/taskflow-api.git
cd taskflow-api

python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt

uvicorn app.main:app --reload
# Acesse http://localhost:8000/docs
```

### Scripts de automação

Os mesmos scripts rodam na sua máquina e dentro do pipeline — nada de comandos
duplicados no YAML que só existem no CI.

```bash
./scripts/lint.sh      # ruff check + ruff format --check
./scripts/test.sh      # pytest com cobertura mínima de 90%
./scripts/build.sh     # build da imagem + teste de fumaça no contêiner
./scripts/deploy.sh    # terraform init/validate/plan/apply
./scripts/destroy.sh   # derruba tudo (use ao encerrar!)
```

---

## 3. Pipeline de Integração Contínua

Definido em [`.github/workflows/ci.yml`](.github/workflows/ci.yml). Dispara em
push para `main`/`develop`, em Pull Requests para `main` e manualmente
(`workflow_dispatch`).

```
lint ──> test (3.12 e 3.14) ──┐
                              ├──> build (imagem + smoke test + push GHCR)
terraform-validate ───────────┘
```

| Job | O que faz | Falha quando |
|---|---|---|
| `lint` | Análise estática com ruff | Estilo, imports ou formatação fora do padrão |
| `test` | pytest em matriz de versões (3.12 e 3.14), com cobertura | Qualquer teste falha ou cobertura < 90% |
| `terraform-validate` | `fmt -check`, `init -backend=false`, `validate` | Sintaxe ou formatação inválida no IaC |
| `build` | Constrói a imagem e valida o health check dentro do contêiner | Build quebra ou a app não sobe |

**Decisões de projeto:**

- `lint` roda primeiro e sozinho porque é a etapa mais barata — falha em
  segundos e evita gastar minutos de runner com código mal formatado.
- `test` e `terraform-validate` são independentes e rodam em paralelo.
- `build` só publica no GHCR quando o commit está em `main`; em Pull Requests a
  imagem é construída e testada, mas não publicada.
- `terraform init -backend=false` permite validar o IaC **sem credenciais AWS**.
  Isso é essencial no Learner Lab, cujas credenciais são de sessão e expiram —
  não haveria como guardá-las em secrets fixos do GitHub.
- Cache de dependências via `actions/setup-python` com `cache: pip`.

---

## 4. Testes automatizados

19 testes divididos em três arquivos:

| Arquivo | Tipo | Cobre |
|---|---|---|
| `tests/test_repository.py` | Unitário | Sequência de IDs, sanitização de entrada, operações em IDs inexistentes |
| `tests/test_tasks_api.py` | Integração | Todos os verbos HTTP, ordenação, filtros, 404 e validação (422) |
| `tests/test_health.py` | Fumaça | Health check e disponibilidade do OpenAPI |

O `pyproject.toml` impõe **cobertura mínima de 90%** via `--cov-fail-under=90`;
a cobertura atual é de **97%**. O isolamento entre testes é garantido pela
fixture `client`, que limpa o repositório antes e depois de cada caso.

```bash
$ ./scripts/test.sh
19 passed — Total coverage: 97.40%
```

---

## 5. Infraestrutura como Código

Terraform 1.10, provider AWS `~> 5.0`. Arquivos em [`infra/`](infra/).

| Arquivo | Recursos |
|---|---|
| `versions.tf` | Versões fixadas, provider e tags padrão |
| `variables.tf` | Variáveis com validação de região e tipo de instância |
| `network.tf` | VPC, Internet Gateway, 2 sub-redes públicas, route table |
| `security.tf` | Security group + regras de ingresso/egresso |
| `compute.tf` | AMI Amazon Linux 2023, EC2, Elastic IP, log group |
| `storage.tf` | Bucket S3 de artefatos (versionado, criptografado, privado) |
| `outputs.tf` | URLs da aplicação, IDs dos recursos |

### Restrições do AWS Academy Learner Lab

O código foi escrito especificamente para o ambiente da disciplina:

| Restrição | Como o código lida com ela |
|---|---|
| Não é possível criar IAM roles | `data "aws_iam_instance_profile" "lab"` referencia a `LabInstanceProfile` já existente na conta |
| Apenas `us-east-1` e `us-west-2` | Bloco `validation` na variável `aws_region` rejeita outras regiões |
| Famílias de instância limitadas | `validation` restringe a `t2`/`t3` de `nano` a `large` |
| Credenciais de sessão expiram | Estado local em vez de backend S3; `deploy.sh` exige as três variáveis exportadas |
| Orçamento de US$ 100 | `t3.micro`, EBS de 8 GB, retenção de logs de 7 dias, ciclo de vida no S3 |

### Boas práticas aplicadas

- Criptografia no volume EBS e no bucket S3
- **IMDSv2 obrigatório** (`http_tokens = "required"`)
- Bloqueio total de acesso público no S3
- SSH desabilitado por padrão (`enable_ssh = false`)
- Regras de SG como recursos separados, permitindo alteração sem recriar o grupo

### Como provisionar

```bash
# 1. No Learner Lab: Start Lab, depois AWS Details > AWS CLI.
#    Copie as três variáveis e exporte no terminal:
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# 2. Configure a imagem publicada pelo seu pipeline
cd infra
cp terraform.tfvars.example terraform.tfvars
# edite container_image = "ghcr.io/levimbraga/taskflow-api:latest"

# 3. Provisione
cd .. && ./scripts/deploy.sh

# 4. Valide
curl $(cd infra && terraform output -raw health_check_url)
# {"status":"ok","version":"1.0.0"}

# 5. AO TERMINAR — sempre!
./scripts/destroy.sh
```

> ⚠️ Recursos esquecidos ligados consomem o crédito de US$ 100 até a conta ser
> desativada e **todos os recursos serem removidos**. Rode `destroy.sh` ao fim
> de cada sessão.

---

## 6. Estrutura do repositório

```
taskflow-api/
├── .github/workflows/ci.yml    # Pipeline de Integração Contínua
├── app/                        # Código da aplicação
│   ├── main.py                 # Rotas FastAPI
│   ├── repository.py           # Camada de persistência
│   └── schemas.py              # Contratos Pydantic
├── tests/                      # Suíte automatizada (19 testes)
├── infra/                      # Terraform
├── scripts/                    # Automação de lint, test, build, deploy
├── Dockerfile                  # Build multi-estágio, usuário não-root
└── pyproject.toml              # Config do pytest, coverage e ruff
```

---

## 7. Próximas fases

- Entrega Contínua: job de deploy automático após o build em `main`
- Monitoramento: dashboards e alarmes no CloudWatch
- Alta disponibilidade: Application Load Balancer + Auto Scaling Group nas duas
  sub-redes já provisionadas
