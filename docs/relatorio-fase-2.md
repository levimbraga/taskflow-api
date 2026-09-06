# Relatório de Entrega — DevOps na Prática

**Aluno:** Levi Maia Braga
**Projeto:** TaskFlow API — <https://github.com/levimbraga/taskflow-api>
**Curso:** Análise e Desenvolvimento de Sistemas — PUCRS

---

## Sumário

1. [Expansão do CI para CD](#1-expansão-do-ci-para-cd)
2. [Containerização e orquestração](#2-containerização-e-orquestração)
3. [Relatório da Fase 1](#3-relatório-da-fase-1)
4. [Relatório da Fase 2](#4-relatório-da-fase-2)
5. [Análise crítica](#5-análise-crítica)
6. [Evidências de execução](#6-evidências-de-execução)

---

## 1. Expansão do CI para CD

### 1.1 O problema a resolver

Ao final da Fase 1 o pipeline sabia dizer se um commit era bom: rodava lint,
testes em duas versões do Python, validava o Terraform e construía a imagem.
O que ele não sabia fazer era **colocar esse commit em produção**. A distância
entre "os testes passaram" e "o código está no ar" continuava sendo percorrida
a mão.

Expandir para entrega contínua exigiu responder a uma pergunta concreta: *como
o GitHub Actions alcança a instância EC2?* O caminho convencional — o pipeline
autentica na AWS e empurra o deploy por SSH ou por `aws ssm send-command` —
esbarra numa restrição do ambiente da disciplina.

O projeto roda no **AWS Academy Learner Lab**, cujas credenciais são de sessão:
elas expiram a cada `Start Lab` e vêm acompanhadas de um `AWS_SESSION_TOKEN`
novo. Não existe credencial estável para guardar em `secrets` do GitHub. A
alternativa moderna a segredos estáticos, a federação por OIDC, exige criar uma
IAM role — exatamente o que a conta do laboratório proíbe. Qualquer pipeline
que empurrasse o deploy quebraria na primeira vez que o laboratório fosse
reiniciado, o que acontece a cada sessão de estudo.

### 1.2 A arquitetura escolhida: entrega *pull-based*

A solução inverte o sentido do fluxo. Em vez de o pipeline empurrar o artefato
para dentro da infraestrutura, a infraestrutura passa a puxá-lo do registro:

> O GitHub Actions apenas **promove** a imagem no GitHub Container Registry.
> Quem detecta a novidade e recria o contêiner é a própria instância EC2,
> através do **Watchtower**, que observa a tag `:latest`.

O ganho não é apenas contornar uma limitação do laboratório; o modelo é
genuinamente mais defensável:

| Aspecto | Deploy *push* (SSH/SSM) | Deploy *pull* (adotado) |
|---|---|---|
| Credenciais da AWS no GitHub | Necessárias | **Nenhuma** |
| Porta 22 | Aberta para as faixas de IP dos runners | **Fechada** |
| Sentido da conexão | Runner → instância (entrada) | Instância → registro (**saída**) |
| IP dinâmico da instância | Precisa ser descoberto pelo pipeline | Irrelevante |
| Natureza da operação | Comando imperativo, pode falhar pela metade | **Estado desejado** declarado por uma tag |

O preço é a latência: o Watchtower verifica o registro a cada 60 segundos, então
há uma janela de até um minuto entre a aprovação e o contêiner novo no ar. Para
o escopo desta disciplina é uma troca claramente vantajosa.

### 1.3 O portão de aprovação manual

Entrega contínua não é implantação automática. O pipeline `cd.yml` executa o job
`promover` sob `environment: producao`. Com **required reviewers** configurados
nas Settings do repositório, o job fica parado, aguardando uma aprovação humana,
antes de tocar no registro.

Para que esse portão tenha valor real foi preciso mudar o job `build` do CI.
Na Fase 1 ele publicava `:sha` **e** `:latest` assim que o commit chegava na
`main`. Como `:latest` é justamente a tag que o Watchtower observa, o deploy
aconteceria sozinho e a aprovação seria decorativa. Hoje o CI publica apenas a
tag do commit — uma **candidata** —, e mover `:latest` é privilégio exclusivo do
CD, depois do aval humano.

Uma segunda decisão: **a imagem não é reconstruída na promoção**. Promover é
apontar novas tags para o mesmo digest que o CI construiu, testou e varreu.
Reconstruir a partir do código-fonte poderia produzir um binário diferente
daquele que passou pelas verificações — dependências transitivas mudam, bases
de imagem são atualizadas. O comando abaixo apenas cria referências:

```yaml
docker buildx imagetools create \
  --tag "${IMAGEM}:${TAG}" \
  --tag "${IMAGEM}:latest" \
  "${IMAGEM}:${SHA}"
```

O job `verificar` fecha o ciclo: consulta o registro e confirma que as duas tags
respondem **e apontam para o mesmo digest** do commit promovido. É o que separa
"o comando de push não deu erro" de "a imagem que a instância vai baixar é
realmente a certa".

### 1.4 Exemplo de uso concreto

A sequência abaixo é o caminho completo de uma mudança, do editor até o
contêiner novo em execução.

#### Passo 1 — O desenvolvedor trabalha em uma branch

A `main` é protegida por *ruleset*: exige Pull Request e todos os checks verdes.
Não há push direto.

```bash
git checkout -b feat/prioridade-urgente
# ... edita app/schemas.py e tests/test_tasks_api.py ...

./scripts/lint.sh     # falha em segundos se o estilo estiver fora do padrão
./scripts/test.sh     # 21 passed — cobertura 97,47% (mínimo exigido: 90%)

git commit -am "feat: adiciona prioridade urgente na criacao de tarefas"
git push -u origin feat/prioridade-urgente
gh pr create --title "Adiciona prioridade urgente" --body "..."
```

**O que acontece:** a abertura do Pull Request dispara o `ci.yml`. O job `lint`
roda sozinho primeiro, por ser o mais barato. Passando ele, disparam em paralelo
`test` (pytest em Python 3.12 e 3.14, com `--cov-fail-under=90`), `security`
(pip-audit, Trivy com relatório SARIF e Gitleaks) e `terraform-validate`. Com os
três verdes, `build` constrói a imagem e sobe o contêiner para exigir uma
resposta de `/health` — em Pull Request a imagem é construída e testada, mas
**não** publicada.

#### Passo 2 — Merge na `main`

```bash
gh pr merge --squash
```

**O que acontece:** o ruleset só libera o merge com os checks verdes. Na `main`
o `ci.yml` roda de novo e, desta vez, publica a imagem candidata:

```
ghcr.io/levimbraga/taskflow-api:9f2c1ab…
```

A tag `:latest` continua apontando para a versão anterior. **Nada foi implantado
ainda.**

#### Passo 3 — O CD é disparado e para, aguardando aprovação

O `cd.yml` é acionado por `workflow_run` assim que o CI conclui com sucesso na
`main`. O job `promover` inicia e imediatamente **para**: o `environment:
producao` exige revisão. O responsável recebe a notificação e vê no resumo qual
commit está sendo promovido.

```bash
gh run list --workflow=cd.yml --limit 1     # status: waiting
```

Quem aprova pode fazê-lo pela interface do GitHub ou pela linha de comando.
Também é possível promover manualmente um commit já validado:

```bash
gh workflow run cd.yml -f motivo="Reimplantacao apos manutencao da instancia"
```

#### Passo 4 — A aprovação promove a imagem

Aprovado o environment, o job retoma e:

1. gera a tag de versão a partir da data e do SHA curto — `2026.09.06-9f2c1ab`,
   ordenável por data e rastreável até o commit exato;
2. aponta `:latest` **e** a tag versionada para o digest já validado;
3. escreve no resumo da execução qual commit, qual digest e quais tags.

O job `verificar` então confirma no registro que as duas tags respondem e
compartilham o digest do commit promovido, com até dez tentativas espaçadas de
15 segundos para absorver a propagação.

#### Passo 5 — A instância puxa sozinha

Na EC2, o Watchtower — subido pelo `user_data` com o profile `deploy` — consulta
o registro a cada 60 segundos. Ao ver que `:latest` mudou de digest:

1. baixa a imagem nova;
2. recria **uma réplica de cada vez** (`WATCHTOWER_ROLLING_RESTART`), de modo que
   a outra continua atendendo o nginx durante a troca;
3. remove a imagem antiga (`--cleanup`), poupando disco na `t3.micro`.

O `--scope taskflow` limita o raio de ação: só contêineres que carregam o rótulo
`com.centurylinklabs.watchtower.scope=taskflow` são atualizados. O Prometheus, o
Grafana e o Loki ficam intocados.

#### Passo 6 — Verificação

```bash
curl http://<ip-da-instancia>/health
# {"status":"ok","version":"1.1.0"}
```

Nenhuma credencial da AWS foi usada pelo GitHub. Nenhuma porta de entrada além
da 80 esteve aberta. O único artefato que atravessou a fronteira foi a imagem,
puxada pela instância.

#### Alternativa manual, com rollback automático

Quando é preciso implantar sem esperar o ciclo do Watchtower — ou validar a
stack antes de promover —, o `deploy-stack.sh` faz o mesmo trabalho com uma
rede de proteção:

```bash
./scripts/deploy-stack.sh 2026.09.06-9f2c1ab
```

O script grava o **ID da imagem** em execução, sobe a nova versão e espera até
90 segundos por uma resposta de `/health` através do nginx. Se ela não vier,
reimplanta o ID gravado e confirma que a versão anterior voltou a atender.

---

## 2. Containerização e orquestração

### 2.1 A imagem: build multi-estágio

O `Dockerfile` separa a construção da execução. O primeiro estágio instala as
dependências em um prefixo isolado; o segundo copia apenas o resultado:

```dockerfile
FROM python:3.12-slim AS builder
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
RUN useradd --create-home --uid 1000 appuser
COPY --from=builder /install /usr/local
COPY --chown=appuser:appuser app/ ./app/
USER appuser
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if ...status==200 else 1)"
```

O que fica de fora da imagem final importa tanto quanto o que entra: o cache do
pip, os arquivos intermediários da instalação e qualquer ferramenta de
compilação. A imagem resultante tem **244 MB** sobre uma base `python:3.12-slim`
de 190 MB — ou seja, a aplicação e todas as suas dependências ocupam cerca de
54 MB.

Duas decisões de segurança estão no próprio Dockerfile: a aplicação roda como
**usuário não-root** (`appuser`, uid 1000), e o `HEALTHCHECK` é interno, o que
permite ao Compose e ao Docker distinguirem "o processo está de pé" de "a
aplicação está respondendo".

### 2.2 A stack orquestrada

O `docker-compose.yml` sobe seis serviços, mais o Watchtower no profile `deploy`:

```
                    ┌─────────────┐
     porta 80  ───> │    nginx    │ ──┬──> app (réplica 1) ──┐
                    └─────────────┘   └──> app (réplica 2) ──┤
                                                             │  /metrics
     porta 9090 ──> Prometheus <────────── (descoberta DNS) ──┘
     porta 3000 ──> Grafana <── Prometheus (métricas)
                            <── Loki <── Promtail <── logs de todos os contêineres
```

A aplicação sobe em **duas réplicas** (`deploy.replicas: 2`) e não expõe porta
no host: só o nginx é publicado. Isso significa que não há caminho para a
aplicação que não passe pelo proxy — os cabeçalhos de segurança e o *rate
limiting* não podem ser contornados.

### 2.3 O balanceamento de carga

Este foi o ponto que mais exigiu atenção. A configuração natural do nginx seria
um bloco `upstream`:

```nginx
upstream app { server app:8000; }   # NÃO funciona como se espera
```

O problema é que o nginx resolve esse nome **uma única vez**, na inicialização.
O DNS interno do Docker devolve os IPs das duas réplicas, mas o nginx guarda o
primeiro e fixa todo o tráfego nele. O balanceamento seria uma ilusão.

A correção é apontar explicitamente o resolver do Docker e usar uma **variável**
no `proxy_pass`, o que obriga o nginx a reresolver o nome a cada requisição:

```nginx
resolver 127.0.0.11 valid=10s ipv6=off;

location / {
    set $backend "app:8000";
    proxy_pass http://$backend;
}
```

A verificação foi empírica: 40 requisições a `/health` através do nginx,
contadas pelo Prometheus por instância:

```
172.20.0.2:8000  ->  20 requisições
172.20.0.7:8000  ->  22 requisições
```

A pequena diferença vem dos health checks internos de cada contêiner, que também
contam. A distribuição é a esperada de um round-robin.

### 2.4 Endurecimento de segurança

**No contêiner da aplicação**, declarado no Compose e confirmado com
`docker inspect`:

| Medida | Efeito |
|---|---|
| `read_only: true` | Sistema de arquivos raiz somente leitura; um invasor não grava binários |
| `cap_drop: [ALL]` | Todas as capabilities do kernel removidas |
| `no-new-privileges:true` | Impede escalonamento via binários *setuid* |
| `tmpfs: [/tmp]` | Devolve apenas a escrita realmente necessária, em memória |
| `USER appuser` | Execução como uid 1000, não como root |
| `logging` com rotação | Máximo de 3 arquivos de 10 MB, para não encher o disco da `t3.micro` |

**No proxy reverso**: `X-Content-Type-Options`, `X-Frame-Options: DENY`,
`Referrer-Policy`, `Content-Security-Policy`, `server_tokens off`, corpo limitado
a 1 MB e *rate limiting* de 30 r/s com burst de 20. Uma rajada de 80 requisições
simultâneas produziu 22 respostas `200` e 58 respostas `429` — e não `503`, o
código padrão do nginx, que sugeriria indisponibilidade do servidor em vez de
excesso de requisições do cliente.

Uma correção feita durante a Fase 2 merece registro. O `/metrics` estava
liberado no nginx para a faixa `172.16.0.0/12`, na intenção de permitir apenas o
Prometheus. Na prática a regra não protegia nada: todo tráfego vindo da rede do
Docker chega traduzido para o endereço do gateway da bridge, que cai justamente
dentro dessa faixa. Como o Prometheus descobre as réplicas por DNS e raspa
`app:8000` **diretamente pela rede interna**, sem passar pelo proxy, não existe
consumidor legítimo da rota através do nginx. A rota passou a ser recusada por
completo, e o Prometheus continua coletando normalmente.

---

## 3. Relatório da Fase 1

### O que foi feito

A Fase 1 entregou a fundação: uma aplicação testável, um pipeline que a verifica
e a infraestrutura descrita como código.

**Aplicação.** Uma API REST de gerenciamento de tarefas em FastAPI, com sete
rotas, contratos validados por Pydantic v2 e uma camada de repositório separada
das rotas. O tamanho é modesto de propósito — o objeto de estudo é a esteira,
não a regra de negócio —, mas a separação em camadas foi mantida porque é ela
que torna a aplicação testável em dois níveis.

**Testes.** Uma suíte dividida por natureza: unitários sobre o repositório,
integração sobre as rotas HTTP e fumaça sobre o health check. O `pyproject.toml`
impõe cobertura mínima de 90% através de `--cov-fail-under=90`, o que transforma
a cobertura em um *check* do pipeline e não em um número decorativo.

**Pipeline de CI.** Quatro jobs em `ci.yml`, encadeados pela dependência real
entre eles: `lint` primeiro por ser o mais barato; `test` em matriz de versões e
`terraform-validate` em paralelo; `build` ao final.

**Infraestrutura como código.** Terraform descrevendo VPC, Internet Gateway,
duas sub-redes públicas em zonas de disponibilidade distintas, route table,
security group com regras declaradas como recursos separados, instância EC2,
Elastic IP, bucket S3 de artefatos e log group no CloudWatch.

### Decisões e o porquê

**Scripts em `scripts/`, e não comandos no YAML.** O pipeline chama
`./scripts/lint.sh` e `./scripts/test.sh`; o desenvolvedor chama exatamente os
mesmos scripts. Isso elimina a classe de problema em que o CI faz algo
sutilmente diferente do que se faz na máquina local, e permite reproduzir uma
falha do pipeline sem tentativa e erro por commits.

**`terraform init -backend=false` no CI.** Valida a sintaxe e a coerência do IaC
**sem credenciais da AWS**. Foi o que permitiu manter a validação da
infraestrutura no pipeline apesar de as credenciais do Learner Lab expirarem.

**Estado do Terraform local.** Um backend S3 com bloqueio em DynamoDB é a prática
recomendada, e o bloco está escrito e comentado no `versions.tf`. Ele foi
deixado desabilitado porque a conta do laboratório é reciclada entre sessões, o
que tornaria o backend remoto uma fonte de instabilidade em vez de proteção.

**Validações nas variáveis.** As restrições do Learner Lab estão codificadas:
`aws_region` aceita apenas `us-east-1` e `us-west-2`; `instance_type` aceita
apenas `t2`/`t3` de `nano` a `large`. O erro aparece no `plan`, com mensagem em
português, em vez de virar uma falha da API da AWS no meio do `apply`.

**`data` em vez de `resource` para o perfil de instância.** A conta do
laboratório não permite criar IAM roles. O código referencia a
`LabInstanceProfile` já provisionada.

### Resultados

- 19 testes passando, com cobertura acima do mínimo exigido de 90%;
- pipeline verde em push e em Pull Request;
- `terraform validate` bem-sucedido, com `fmt -check` limpo;
- imagem publicada no GHCR a cada commit na `main`;
- infraestrutura provisionável com um comando e destruível com outro.

---

## 4. Relatório da Fase 2

### O que foi feito

**Varreduras de segurança no CI.** Um job `security` que ataca três superfícies
distintas: `pip-audit` nas dependências Python, **Trivy** no sistema operacional
e nas bibliotecas que compõem a imagem, e **Gitleaks** sobre o histórico completo
de commits. O resultado do Trivy é publicado em **SARIF na aba Security** do
repositório, onde cada achado vira um alerta rastreável com severidade e versão
de correção.

**Pipeline de entrega contínua.** O `cd.yml`, com o modelo pull-based e o portão
de aprovação manual descritos na seção 1.

**Orquestração em contêineres.** O `docker-compose.yml` com nginx, duas réplicas
da aplicação e a pilha de observabilidade, descrito na seção 2.

**Observabilidade completa.** Três camadas, todas provisionadas por código:
métricas (a aplicação expõe `/metrics`; o Prometheus descobre as réplicas por
DNS), logs (Promtail lê o socket do Docker, rotula por serviço e envia ao Loki)
e painéis (o Grafana provisiona os dois datasources e um dashboard de seis
painéis). Na EC2, o agente do CloudWatch replica os logs para um log group,
dando uma cópia que sobrevive à destruição da instância.

**Terraform executando a stack.** O `user_data` deixou de rodar um contêiner
solto. Ele instala o Docker e o plugin do Compose, clona o repositório para obter
o `docker-compose.yml` e o diretório `ops/`, escreve um `.env` com permissão
`600` contendo a senha do Grafana e sobe a stack com `--profile deploy`.

### Decisões e o porquê

**O CI parou de publicar `:latest`.** Foi a mudança mais importante da fase, e
não é óbvia à primeira vista. Como o Watchtower observa `:latest`, manter a
publicação no CI faria o deploy acontecer automaticamente ao merge, tornando o
portão de aprovação puramente decorativo. Hoje o CI publica uma candidata
identificada pelo SHA, e mover `:latest` é ato exclusivo do CD.

**Promoção por digest, sem reconstruir.** Reconstruir a imagem na promoção
poderia gerar um binário diferente do que passou pelos testes e pelas varreduras.

**Duas passagens do Trivy.** A primeira gera o SARIF e precisa terminar com
sucesso para que o relatório chegue à aba Security mesmo havendo achados; a
segunda roda com `exit-code: 1` e é a que efetivamente bloqueia o pipeline.
Invertida a ordem, um achado impediria a publicação do próprio relatório que o
documenta.

**`--ignore-unfixed` no Trivy.** Falhar o build por uma vulnerabilidade sem
correção disponível não protege ninguém: não há ação possível além de trocar a
imagem base. O critério adotado é acionável — falha apenas no que pode ser
corrigido atualizando um pacote.

**Actions fixadas por versão.** Todas as actions de terceiros são referenciadas
por tag de versão (`@v4`, `@v0.36.0`). Referenciar `@master` significaria
executar, com as permissões do repositório, código que pode mudar sem aviso.

**Painéis fechados por padrão.** A variável `observability_ingress_cidr` tem
valor padrão `127.0.0.1/32`, que na prática mantém as portas 3000 e 9090
fechadas até que o operador declare de qual endereço vai acessar. Uma
`validation` **rejeita** `0.0.0.0/0`: é uma decisão que o código não permite
tomar por descuido. A senha do Grafana é uma variável `sensitive = true` **sem
valor padrão**, o que obriga a defini-la conscientemente.

**Rótulos de escopo do Watchtower.** O Watchtower foi configurado com `--scope
taskflow`, mas os contêineres não carregavam o rótulo correspondente — a
configuração não teria efeito algum. O rótulo
`com.centurylinklabs.watchtower.scope` foi adicionado ao serviço da aplicação e
ao próprio Watchtower.

**Rollback por ID de imagem, não por tag.** O `deploy-stack.sh` guardava o nome
da tag em execução antes de trocar de versão. Como a implantação normal usa
sempre `:latest`, reverter reapontaria para a mesma imagem quebrada que acabara
de subir — o rollback não reverteria nada. O script passou a gravar o ID da
imagem, que identifica o binário exato que estava no ar.

### Resultados

Todos os números abaixo foram obtidos de execuções reais, transcritas na
[seção 6](#6-evidências-de-execução).

| Verificação | Resultado |
|---|---|
| `./scripts/lint.sh` | ruff check e ruff format sem apontamentos, 11 arquivos |
| `./scripts/test.sh` | **21 testes**, cobertura total de **97,47%** (mínimo: 90%) |
| `terraform fmt -check` e `validate` | Formatação limpa, configuração válida |
| `docker compose config` | Sem erros |
| Stack em execução | 7 contêineres: 2 réplicas, nginx, Prometheus, Grafana, Loki, Promtail |
| Prometheus | **as duas réplicas** como `up`, descobertas por DNS |
| Balanceamento | 20 e 22 requisições, distribuição equilibrada |
| Grafana | Responde na 3000; 2 datasources e 1 dashboard de 6 painéis provisionados |
| Loki | Logs das duas réplicas indexados e consultáveis por serviço |
| `pip-audit` | Nenhuma vulnerabilidade conhecida |
| Trivy | **0** achados HIGH/CRITICAL com correção disponível |
| Gitleaks | Nenhum segredo encontrado |
| Rate limiting | 22 respostas `200` e 58 respostas `429` em uma rajada de 80 |
| Rollback | Imagem defeituosa detectada e revertida automaticamente |

---

## 5. Análise crítica

Nenhuma das limitações abaixo é acidental: todas foram escolhas conscientes
diante do escopo da disciplina e das restrições do ambiente. Registrá-las com
honestidade vale mais do que sugerir uma solidez que o projeto não tem.

### 5.1 Persistência em memória

**A limitação.** O `TaskRepository` guarda as tarefas em um dicionário Python.
Os dados não sobrevivem ao reinício do contêiner. Pior: com **duas réplicas**,
cada uma tem o seu próprio dicionário, e o nginx distribui as requisições entre
elas. O efeito é observável — a mesma tarefa, consultada quatro vezes seguidas,
alternou entre `200` e `404`:

```
POST   /tasks     -> {"id":1, ...}
PATCH  /tasks/1   -> {"detail":"Tarefa 1 não encontrada"}
GET    /tasks/1   -> 200 | 200 | 404 | 200
```

**Por que ficou assim.** Foi deliberado. O objeto de estudo da disciplina é a
esteira de CI/CD, e um banco de dados acrescentaria migrações e um serviço com
estado sem ensinar nada de novo sobre DevOps.

**A melhoria.** Trocar a implementação do repositório por PostgreSQL. O custo é
baixo justamente porque a arquitetura já previu a troca: a classe
`TaskRepository` expõe a mesma interface que um repositório com banco relacional
exporia, e nenhuma rota conhece a implementação. Seria acrescentar o serviço ao
Compose, um RDS ao Terraform, e substituir a classe — as rotas ficam intocadas.
Só então a replicação passaria a ser realmente útil.

### 5.2 Estado do Terraform local

**A limitação.** O `terraform.tfstate` fica na máquina de quem aplica. Não há
bloqueio concorrente, não há histórico compartilhado, e perder o arquivo
significa perder o vínculo entre o código e os recursos que ele criou — que
passariam a ter de ser removidos a mão, um a um, com o orçamento correndo.

**Por que ficou assim.** A conta do Learner Lab é reciclada entre sessões. Um
backend S3 apontando para um bucket que pode não existir mais seria uma fonte
de instabilidade em vez de proteção.

**A melhoria.** O bloco `backend "s3"` está escrito e comentado no `versions.tf`,
com bucket, chave, região, tabela de bloqueio e criptografia. Em uma conta AWS
permanente, bastaria descomentá-lo. Um passo intermediário viável já hoje seria
versionar o estado cifrado com `git-crypt` ou SOPS.

### 5.3 Ausência de alta disponibilidade

**A limitação.** As duas réplicas rodam na **mesma instância EC2**. Isso protege
contra a falha de um processo e permite a troca de versão sem interrupção, mas
não protege contra nada que atinja a instância: uma falha de hardware, um
problema na zona de disponibilidade ou um `terraform destroy` derrubam o
serviço inteiro. O `t3.micro` também é um teto real de capacidade.

**Por que ficou assim.** O orçamento de US$ 100 do laboratório e a natureza
efêmera da conta desaconselham manter um balanceador e várias instâncias ligados.

**A melhoria.** A base já está pronta: a VPC tem **duas sub-redes públicas em
zonas de disponibilidade distintas**, provisionadas na Fase 1 exatamente com
esse fim. O caminho é um Application Load Balancer distribuindo entre um Auto
Scaling Group com instâncias nas duas sub-redes, usando `/health` como health
check do target group. O ALB assumiria o papel do nginx no balanceamento entre
máquinas, e o nginx continuaria dentro de cada instância.

### 5.4 Credenciais efêmeras do Learner Lab

**A limitação.** As credenciais expiram a cada `Start Lab`. Nenhum provisionamento
de infraestrutura pode ser automatizado pelo pipeline: `terraform apply` continua
sendo um ato manual, executado por quem tem a sessão aberta. A entrega contínua
do projeto cobre a **aplicação**, não a **infraestrutura**.

**A melhoria.** Em uma conta AWS permanente, a resposta correta não é guardar
chaves em `secrets`, mas **federação por OIDC**: o GitHub Actions troca um token
de identidade por credenciais temporárias de uma IAM role que confia no
repositório. Isso elimina segredos de longa duração e permite restringir a role
a uma branch específica. O Learner Lab impede exatamente isso, por não permitir
criar roles — e é o que motivou a arquitetura pull-based. Vale notar que o
modelo pull continuaria sendo uma boa escolha mesmo sem a restrição: ele não é
apenas um contorno.

### 5.5 Ausência de TLS

**A limitação.** O tráfego entre o cliente e o nginx é HTTP puro. Credenciais,
corpos de requisição e respostas trafegam legíveis. O `Content-Security-Policy` e
os demais cabeçalhos perdem muito do sentido sem um canal cifrado — um atacante
na rede pode simplesmente removê-los.

**Por que ficou assim.** TLS exige um nome de domínio, e o endereço da instância
é um IP elástico que muda a cada recriação. Não há domínio disponível no
laboratório.

**A melhoria.** Com um domínio: certificado gratuito no ACM terminando no ALB —
a opção mais simples, sem renovação a gerenciar. Sem ALB, `certbot` com
renovação automática e terminação no próprio nginx. Em ambos os casos, redirecionamento
de 80 para 443 e um cabeçalho `Strict-Transport-Security`.

### 5.6 A janela de até 60 segundos do Watchtower

**A limitação.** O Watchtower consulta o registro em intervalos de 60 segundos.
Entre a aprovação no environment e o contêiner novo no ar pode passar até um
minuto. Um *hotfix* urgente não é instantâneo. Há ainda um efeito colateral: o
GitHub Actions reporta o deploy como concluído quando a **promoção** termina,
não quando a instância termina de aplicá-la — o pipeline não sabe se a
implantação deu certo.

**Por que ficou assim.** É a contrapartida direta de não ter caminho de entrada
na instância. Reduzir o intervalo aumentaria as consultas ao registro sem
resolver o problema de fundo.

**As melhorias, em ordem de esforço:**

1. **Confirmação por métrica.** A aplicação já expõe `/metrics` e o Prometheus já
   coleta. Adicionar a versão como rótulo permitiria um alerta que dispara se a
   versão em execução não corresponder à promovida após alguns minutos.
2. **Notificação de retorno.** O Watchtower suporta notificações; a instância
   poderia avisar um canal ao concluir a atualização, fechando o laço para quem
   aprovou.
3. **Webhook em vez de sondagem.** O Watchtower aceita ser acionado por uma
   requisição HTTP. Exporia um endpoint autenticado na instância, o que reintroduz
   uma porta de entrada — a troca precisaria ser avaliada.
4. **Um agente de GitOps.** Em um cluster, um controlador que reconcilia o estado
   declarado em um repositório resolveria simultaneamente a latência e a
   confirmação. É a evolução natural, e também a de maior custo.

### 5.7 Outras observações

- **Testes só de unidade e integração.** Não há testes de carga nem de caos. As
  afirmações sobre balanceamento e rollback foram verificadas manualmente, uma
  vez cada, e não a cada execução do pipeline.
- **Duas linhas não cobertas.** A cobertura de 97,47% deixa duas linhas de
  `app/main.py` sem exercício: o retorno bem-sucedido de `GET /tasks/{id}` — os
  testes só consultam um id inexistente por essa rota — e o ramo de `404` do
  `PATCH`. Dois casos de teste fechariam a lacuna, e o fato de o percentual
  estar confortavelmente acima do mínimo de 90% é justamente o que permite que
  ela passe despercebida: a métrica agregada esconde *quais* caminhos faltam.
- **O Promtail lê o socket do Docker.** É o modo mais simples de coletar os logs
  de todos os contêineres, mas dá ao Promtail acesso de leitura ao daemon.
  Montar o socket, ainda que como somente leitura, é uma concessão consciente.
- **Sem alertas configurados.** O Grafana mostra os dados, mas ninguém é avisado
  quando a taxa de erro sobe. Regras de alerta no Prometheus seriam o próximo
  passo natural da observabilidade.

---

## 6. Evidências de execução

Todas as saídas abaixo foram obtidas na execução real dos comandos.

### Lint

```
$ ./scripts/lint.sh
>> ruff check (lint)
All checks passed!
>> ruff format --check (formatação)
11 files already formatted
>> Lint concluído com sucesso
```

### Testes e cobertura

```
$ ./scripts/test.sh
Name                Stmts   Miss  Cover   Missing
-------------------------------------------------
app/__init__.py         1      0   100%
app/main.py            33      2    94%   47, 64
app/repository.py      28      0   100%
app/schemas.py         17      0   100%
-------------------------------------------------
TOTAL                  79      2    97%
Required test coverage of 90% reached. Total coverage: 97.47%
======================== 21 passed, 1 warning in 0.12s =========================
```

### Infraestrutura como código

```
$ cd infra && terraform fmt -check -recursive && terraform validate
Success! The configuration is valid.
```

### Stack de contêineres

```
$ docker compose ps --format "table {{.Service}}\t{{.Status}}"
SERVICE      STATUS
app          Up (healthy)
app          Up (healthy)
grafana      Up
loki         Up
nginx        Up
prometheus   Up
promtail     Up

$ curl -s localhost/health
{"status":"ok","version":"1.0.0"}
```

### Prometheus enxergando as duas réplicas

```
$ curl -s 'localhost:9090/api/v1/targets'
prometheus      http://localhost:9090/metrics     health=up
taskflow-api    http://172.20.0.2:8000/metrics    health=up
taskflow-api    http://172.20.0.7:8000/metrics    health=up
```

### Grafana

```
$ curl -s localhost:3000/api/health
{"database": "ok", "version": "11.5.1"}

Datasources provisionados: Prometheus (http://prometheus:9090), Loki (http://loki:3100)
Dashboard provisionado:    "TaskFlow - Visao Geral", 6 painéis
```

### Varreduras de segurança

```
$ pip-audit --requirement requirements.txt --strict
No known vulnerabilities found

$ trivy image --severity HIGH,CRITICAL --ignore-unfixed taskflow-api:scan
Detected OS: debian 13.6 — 87 pacotes analisados
taskflow-api:scan (debian 13.6)   0 achados

$ gitleaks detect --no-banner --redact
no leaks found
```

### Endurecimento do contêiner

```
$ docker inspect taskflow-app-1
ReadonlyRootfs=true  CapDrop=[ALL]  SecurityOpt=[no-new-privileges:true]  Usuario=appuser

$ docker exec taskflow-app-1 id
uid=1000(appuser) gid=1000(appuser) groups=1000(appuser)
```

### Rate limiting e bloqueio do /metrics

```
$ for i in $(seq 1 80); do curl -s -o /dev/null -w '%{http_code}\n' localhost/tasks & done | sort | uniq -c
     22 200
     58 429

$ curl -s -o /dev/null -w '%{http_code}\n' localhost/metrics
403
```

### Rollback automático

Uma imagem propositalmente defeituosa foi implantada para exercitar o caminho de
falha:

```
$ ./scripts/deploy-stack.sh taskflow-api:quebrada
>> Imagem alvo: taskflow-api:quebrada
>> Versão atual em execução: taskflow-api:local (sha256:dfbe066c53d1)
>> Subindo a stack
!! A aplicação não respondeu ao health check
nginx-1  | "GET /health HTTP/1.1" 502
>> Executando rollback para taskflow-api:local (sha256:dfbe066c53d1)
>> Rollback concluido: a versao anterior respondeu na tentativa 2
$ echo $?
1
```

O código de saída `1` é o esperado: o deploy falhou, ainda que o rollback tenha
sido bem-sucedido.

### O pipeline executado no Pull Request

O `ci.yml`, já com o job `security`, rodou no Pull Request da Fase 2. Os seis
jobs terminaram com sucesso, e os horários confirmam que `security`, `test`
(3.12) e `test` (3.14) começaram no mesmo instante — o paralelismo é real, não
apenas declarado:

```
Lint e formatação                 21:20:49 -> 21:21:04
Validação do Terraform            21:20:49 -> 21:21:03
Varreduras de segurança           21:21:07 -> 21:22:03
Testes (Python 3.14)              21:21:07 -> 21:21:21
Testes (Python 3.12)              21:21:07 -> 21:21:26
Build da imagem e teste de fumaça 21:22:05 -> 21:22:24
```

O `build` só começou às 21:22:05, depois que as três etapas anteriores
terminaram. O relatório SARIF do Trivy chegou à aba Security do repositório,
registrado sob a categoria `trivy-imagem`, sem nenhum alerta em aberto.

### O que não foi possível executar

Por honestidade, fica registrado o que **não** pôde ser verificado no ambiente
de desenvolvimento:

- **`terraform apply` na AWS.** Exige uma sessão ativa do Learner Lab com
  credenciais válidas. O código foi verificado com `terraform validate`, com
  `fmt -check` e com a renderização do `user_data.sh.tftpl`, cujo script
  resultante foi validado sintaticamente com `bash -n` — mas a instância não foi
  criada.
- **Uma execução completa do `cd.yml`.** O pipeline de CD depende do environment
  `producao` existir nas Settings do repositório, o que não pode ser feito por
  código, e só é disparado por um CI verde na `main`. A sintaxe do workflow foi
  validada e a lógica dos jobs revisada, mas a primeira execução real acontecerá
  após o merge e a configuração manual descrita no README.
- **O Watchtower detectando uma promoção real.** Depende dos dois itens acima.

---

Relatório elaborado por **Levi Maia Braga**.
