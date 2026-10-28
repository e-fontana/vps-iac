# AGENTS.md

Instruções para assistentes de IA que trabalham neste repositório. Para o conteúdo completo, a documentação está em
[docs/README.md](docs/README.md) (comece pelo [guia para assistentes](docs/suporte/para-assistentes-de-ia.md)).

## O projeto em 5 linhas
- Uma VPS no Always Free da Oracle (**ARM, `arm64`**) rodando **k3s + ArgoCD (GitOps)**, acessível **só pela VPN Tailscale**.
- Hospeda a API NestJS (`api.eduardofontana.dev`, repositório separado `e-fontana/api`), Postgres, Redis e SeaweedFS (S3) compartilhados, e a observabilidade (Alloy → Prometheus, Loki, Tempo; Grafana).
- O ArgoCD aplica o que está em `gitops/` no `main`. Segredos **não** vão para o Git.
- IP da VPS na VPN: `100.95.76.83`. Comandos de cluster: `ssh ubuntu@100.95.76.83 'sudo k3s kubectl ...'`.
- Idioma do projeto: **português** (docs, comentários, mensagens dos scripts). Commits em inglês.

## Mapa do repositório
| Caminho | O que é |
|---|---|
| `terraform/` | VPS e rede na Oracle (`modules/network`, `modules/compute`, `envs/prod`) |
| `gitops/apps/` | AppProjects e uma Application por grupo (o `root` lê só aqui) |
| `gitops/groups/<grupo>/` | Uma Application por serviço (`networking`, `observability`, `infra`, `workloads`) |
| `gitops/manifests/` | YAML/Kustomize que as Applications aplicam (api, postgres, redis, seaweedfs, grafana-dashboards...) |
| `templates/` | Scripts de provisionamento e modelos de Dockerfile/CI para aplicações |
| `docs/` | Toda a documentação, por área |

## Comandos
```bash
make help | init | validate | fmt | plan | apply   # Terraform (precisa de TF_VAR_tailscale_auth_key para plan/apply)
bash -n templates/*/*.sh                              # checa a sintaxe dos scripts
kubectl kustomize gitops/manifests/<pasta>            # renderiza um Kustomize localmente
```
Não há suíte de testes automatizada neste repositório. A verificação é feita à mão (veja "Como verificar").

## Regras que não se negociam
1. **Nunca imprima, grave ou peça segredos** (senhas, tokens, chaves do S3, conteúdo de Secrets). Scripts novos geram o valor
   aleatório (`openssl rand`), passam por stdin/`--from-env-file=/dev/stdin` e **nunca o exibem**. Não use `kubectl get secret -o yaml` em respostas.
   `s3.configure` do `weed shell` imprime chaves: filtre a saída (só os nomes) ou não a mostre.
2. **Commit e push só quando o usuário pedir.** Faça commits pequenos e por assunto (um por mudança lógica), mensagem em
   inglês no estilo `feat(scope): ...` / `fix(scope): ...`, com a linha de co-autoria exigida pelo ambiente. Nunca `--no-verify`,
   nunca force-push.
3. **Ações com efeito no cluster, no GitHub ou na Oracle** (criar/alterar Secrets, `Sync`, `terraform apply`, apagar bucket ou
   banco, rodar scripts de `templates/` contra a VPS) são do usuário: explique o que será criado e **peça confirmação**. Consultas
   somente leitura (`get`, `describe`, `logs`, `query` no Prometheus) podem ser feitas sem pedir.
4. **Operações destrutivas:** olhe o alvo antes; nunca `docker volume prune` ou equivalente em massa; apagar bucket apaga os objetos.
5. **Relate com honestidade** o que foi e o que não foi testado. Não afirme "funciona" sem ter verificado.

## Convenções
### GitOps
- Um arquivo por serviço em `gitops/groups/<grupo>/`, com `project: <grupo>` e o label `group: <grupo>`; ondas via `argocd.argoproj.io/sync-wave`.
- Application **automática** por padrão (`syncPolicy.automated`). **Manual** só quando precisa de Secrets criados antes
  (`postgres`, `api`): documente o motivo num comentário no topo do arquivo. Applications automáticas que exigem Secrets
  (`redis`, `seaweedfs`) exigem o script **antes do `git push`**.
- Não declare `directory.recurse: false` (o ArgoCD o remove e a Application fica `OutOfSync`).
- Versões de charts e imagens fixas (nada de `latest`). Imagens para **`linux/arm64`**.
- Comentário no topo de cada Application: o que é, pré-requisitos (Secrets) e a documentação relacionada (`docs/...`).
- Recursos pequenos: a VPS é limitada. Defina `requests` e `limits` de memória.
- Hooks do ArgoCD para tarefas pontuais (migração: `PreSync`; bucket: `PostSync`), com `hook-delete-policy`.

### Scripts em `templates/`
- `#!/usr/bin/env bash` + `set -euo pipefail`. Cabeçalho com uso, exemplo, o que cria e como desfazer.
- **Idempotência segura:** se o recurso já existe, abortar **sem alterar nada**; se falhar no meio, **desfazer o que a própria execução criou**.
- Validar os argumentos com regex; variável `KUBECTL` (padrão `sudo k3s kubectl`) para rodar de fora via `ssh`.
- Segredos só por stdin; saída só com mensagens de status.

### Documentação (`docs/`)
- Documento novo ou alterado: mantenha o **cabeçalho padrão** (*Resumo*, *Para quem*, *Palavras-chave*), as seções
  *Como saber que deu certo* e *Se der errado*, e *Veja também*. Linguagem simples; explique ou linke o termo técnico no glossário.
- Atualize junto: o índice [docs/README.md](docs/README.md), a tabela de [solução de problemas](docs/suporte/solucao-de-problemas.md)
  e o [glossário](docs/comecando/glossario.md) quando surgir sintoma ou termo novo.
- **Nunca documente algo como testado se não foi.** Diga o que não foi verificado.
- Mudou um comportamento (gatilho do CI, Secret, nome de arquivo)? Procure e corrija **todas** as menções (`grep -rn`), inclusive os
  comentários nos YAMLs, que referenciam `docs/...`.
- Valide os links relativos depois de mover ou renomear arquivos.

### Terraform
- `terraform/envs/prod` é onde se roda. `user_data` está em `lifecycle.ignore_changes`: mudar o bootstrap **recria a VM**, então só com autorização.
- `terraform.tfvars`, `*.tfstate` e `*.pem` ficam fora do Git.

## Como verificar (o que já foi usado neste projeto)
- **Scripts:** testados com um `kubectl` falso e/ou contra Postgres, Redis e SeaweedFS reais em Docker (mesmas imagens do cluster).
  Teste também o caminho de **falha** (rollback) e o de **recurso já existente**.
- **Manifests:** `kubectl kustomize <pasta>` e `helm template` com os valores da Application; leia o chart quando precisar
  confirmar um comportamento (ex.: onde `dashboardsConfigMaps` monta o volume).
- **Consultas de dashboards:** execute cada expressão contra o Prometheus/Tempo do cluster antes de commitar.
- **Cluster (somente leitura):** `argocd get applications`, `get pods,secrets`, `describe`, `logs`.
- Se algo só foi testado em `amd64`, em Docker local ou sem o cluster, **diga isso**.

## Armadilhas já encontradas
- **SigV4 + OpenTelemetry:** cabeçalho acrescentado ao S3 antes da assinatura (ex.: `traceparent`) é reescrito pela instrumentação
  `http` e a assinatura falha (403, `UnknownError`). Registre-o em `finalizeRequest` com `priority: 'low'`.
- **`weed shell s3.configure`** formata o JSON com **dois espaços** (`"name":  "x"`): use regex com `[[:space:]]*`, não string exata.
- **SeaweedFS:** com o disco da VPS acima de 95%, `minFreeSpace=5` bloqueia gravações.
- **Redis ACL:** `SCAN` ainda lista os nomes das chaves de todos; a API precisa prefixar as chaves com `<app>:`.
- **GHCR:** exige PAT *classic* com `read:packages` para pull (fine-grained não é aceito); pacotes novos nascem privados.
- **GitHub Actions:** secret de *environment* só é visível para jobs que declaram `environment:`.
- **Secrets antes do Sync:** sem eles o pod fica em `CreateContainerConfigError` (`secret "x" not found`).
- **Prisma:** a imagem final é podada e não migra; as migrações rodam no Job `PreSync` com a imagem `api-migrate`.
- **Shell:** o usuário usa fish; em comandos para ele, `export VAR=...` vira `set -x VAR ...`. Scripts do repositório são bash.

## Onde olhar primeiro
| Preciso de... | Abra |
|---|---|
| Entender o projeto | [Visão geral](docs/comecando/visao-geral.md) |
| Publicar/atualizar a API | [Publicar a API](docs/aplicacoes/publicar-a-api.md) |
| CI/CD e tokens | [CI/CD](docs/aplicacoes/ci-cd.md), [Imagem privada e tokens](docs/aplicacoes/imagem-privada-e-tokens.md) |
| Diagnosticar um erro | [Solução de problemas](docs/suporte/solucao-de-problemas.md) |
