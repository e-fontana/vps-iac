# Publicar a API (`api.eduardofontana.dev`)

> **Resumo:** tudo o que precisa existir no cluster e como acontece o deploy da API NestJS: Secrets, DNS, CI, sync e conferência.
> **Para quem:** quem vai publicar ou atualizar a API. **Dificuldade:** intermediária.
> **Palavras-chave:** api, deploy, publicar, api-db, api-redis, api-s3, ghcr-pull, secret not found, CreateContainerConfigError, sync, release, health, kustomization, imagem de teste, whoami.

## O que é
A Application `api` (`gitops/groups/workloads/api.yaml`, **sem sync automático**) aplica `gitops/manifests/api`: namespace `api`, a API (Deployment + Service), um Job de migração (hook `PreSync`) e um Ingress em `https://api.eduardofontana.dev`, só pela VPN.

Enquanto o `kustomization.yaml` aponta os placeholders (`traefik/whoami` e `busybox`), a API roda uma imagem de teste: serve para validar DNS, TLS e Ingress antes de o CI publicar a imagem real.

## Passo 1: criar os Secrets (na VPS; nada vai ao Git)
O Deployment usa `envFrom` dos três primeiros; o `ghcr-pull` serve para baixar a imagem privada. **Crie todos antes do primeiro Sync.**

| Secret (namespace `api`) | Conteúdo | Como criar (da raiz do repositório) |
|---|---|---|
| `api-db` | `DATABASE_URL` (banco e usuário `api`) | `ssh ubuntu@100.95.76.83 'bash -s -- api api api-db' < templates/postgres/new-database.sh` |
| `api-redis` | `REDIS_URL` (usuário `api`, chaves `api:*`) | `ssh ubuntu@100.95.76.83 'bash -s -- api api api-redis' < templates/redis/new-user.sh` |
| `api-s3` | chaves do bucket `api`, `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION` | `ssh ubuntu@100.95.76.83 'bash -s -- api api api-s3' < templates/seaweedfs/new-bucket.sh` |
| `ghcr-pull` | token de pull do GHCR (imagem privada) | `KUBECTL="ssh ubuntu@100.95.76.83 sudo k3s kubectl" bash templates/api/create-pull-secret.sh api ghcr-pull` |

O `api-tls` (certificado do Ingress) o cert-manager cria sozinho. Os scripts abortam sem alterar nada se o recurso já existe, e desfazem o que criaram se falharem no meio. O token do `ghcr-pull` está explicado em [Imagem privada e tokens](imagem-privada-e-tokens.md).

**Conferir o que falta:**
```bash
ssh ubuntu@100.95.76.83 'sudo k3s kubectl -n api get secrets'
```
Devem existir `api-db`, `api-redis`, `api-s3`, `ghcr-pull` e `api-tls`.

## Passo 2: DNS
Na Cloudflare, registro `A` `api` → `100.95.76.83`, com o proxy desligado.

## Passo 3: código e CI (repositório da API)
Veja [CI/CD](ci-cd.md): Dockerfile, `ci.yml`, `deploy.yml`, o `GITOPS_TOKEN` e os checks obrigatórios do PR.

## Passo 4: o fluxo do deploy
| Evento | O que roda |
|---|---|
| push em qualquer branch | `ci.yml`: lint, testes, `build` e build `arm64` das imagens (sem publicar) |
| push na `main` | `deploy.yml`, só o `build`: publica `ghcr.io/<dono>/api:<sha>` e `api-migrate:<sha>` |
| release publicada ou disparo manual | `build` + `deploy`: grava as duas tags em `gitops/manifests/api/kustomization.yaml` |

Depois do commit do CI neste repositório, o ArgoCD mostra a Application `api` como `OutOfSync`. Clique em **Sync**: o Job `api-migrate` (`PreSync`) aplica as migrações e só então o Deployment é atualizado. Se a migração falhar, a versão antiga continua no ar (`sudo k3s kubectl -n api logs job/api-migrate`).

Um push na `main` sozinho **não** faz deploy. Para voltar ao deploy automático, restaure o bloco `syncPolicy.automated` em `gitops/groups/workloads/api.yaml` (está comentado no arquivo).

## Como saber que deu certo
```bash
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl -n api get pods,certificate,jobs
curl -s https://api.eduardofontana.dev/v1/health/ready    # com a VPN ligada
```
O `/v1/health/ready` deve responder 200 e `https://api.eduardofontana.dev/docs` deve abrir o Swagger (localmente a imagem respondeu 200 nos dois). Antes do primeiro deploy real, `curl https://api.eduardofontana.dev/` devolve os cabeçalhos da requisição (imagem de teste).

## Se der errado
| Sintoma | O que fazer |
|---|---|
| `secret "api-s3" not found` (ou outro) | Crie o Secret da tabela do passo 1; o pod sobe sozinho (ou `rollout restart deploy/api`). |
| `ImagePullBackOff` | Falta ou expirou o `ghcr-pull`, ou o pacote é privado sem token. Veja [Imagem privada e tokens](imagem-privada-e-tokens.md). |
| `/v1/health/ready` responde 503 com erro em `storage` | Veja a armadilha de assinatura em [Armazenamento S3](../servicos/armazenamento-s3.md). |
| Sync trava no `PreSync` | A migração falhou: `kubectl -n api logs job/api-migrate`. |
| `exec format error` | Imagem `amd64`; a VPS é `arm64`. |

## Veja também
- [Checklist de uma aplicação nova](checklist-nova-aplicacao.md) · [Migrações do banco](migracoes-do-banco.md) · [Dashboard da API](../observabilidade/dashboard-da-api.md)
