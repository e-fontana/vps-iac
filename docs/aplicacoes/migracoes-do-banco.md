# Migrações do banco (Prisma)

> **Resumo:** como a estrutura do banco da API (tabelas e colunas) é atualizada automaticamente antes de cada deploy, por um Job do ArgoCD.
> **Para quem:** quem altera o schema do banco da aplicação. **Dificuldade:** intermediária.
> **Palavras-chave:** migração, prisma, migrate deploy, presync, hook, api-migrate, migrate-image, Job, schema, banco, rollback.

## Como funciona
Uma **migração** é um script que altera a estrutura do banco. A API usa Prisma. O padrão é um **Job do ArgoCD no hook `PreSync`**, que roda e termina com sucesso **antes** de o ArgoCD atualizar o Deployment: `gitops/manifests/api/migrate-job.yaml`.

- **Imagem separada.** A imagem final da aplicação é podada (`pnpm prune --prod`) e não tem o CLI do Prisma nem a pasta `prisma/`, então não consegue migrar. O `Dockerfile` tem um alvo `migrate` (`docker build --target migrate`) com as duas coisas. O CI publica as duas imagens (`api` e `api-migrate`) e atualiza as duas tags (`api-image` e `migrate-image`) no `kustomization.yaml`.
- **Sem migrações pendentes, o Job não faz nada** (`No pending migrations to apply`), então roda em todo deploy sem custo.
- **Se a migração falhar, o deploy para:** o `PreSync` falha e a versão antiga da API continua no ar.
- **Compatibilidade:** a migração roda **antes** de a versão nova subir, então precisa ser compatível com a versão antiga (adicione colunas e tabelas primeiro, remova só num deploy posterior).
- **Pré-requisitos:** a namespace `api` e os Secrets `api-db` e `ghcr-pull` já existem (o `PreSync` roda antes do resto da Application).
- **Enquanto o kustomization aponta o placeholder** (`busybox`), o Job termina na hora e não migra nada.

## Como ver o resultado
```bash
ssh ubuntu@100.95.76.83 'sudo k3s kubectl -n api get jobs'
ssh ubuntu@100.95.76.83 'sudo k3s kubectl -n api logs job/api-migrate'
```
O último Job fica no cluster e é recriado no deploy seguinte.

## O que foi testado
- A imagem `migrate` (amd64) aplicou as 2 migrações da API num Postgres vazio em 2 segundos, como usuário não root, e a segunda execução não fez nada.
- O CI construiu a imagem `migrate` em `arm64` (a arquitetura da VPS) com sucesso, e no cluster, o Job `api-migrate` apareceu `Completed` e o pod da API ficou `Running`.

## Se der errado
| Sintoma | Causa provável |
|---|---|
| Sync trava no `PreSync` | A migração falhou: leia `kubectl -n api logs job/api-migrate`. |
| Job em `CreateContainerConfigError` | Falta o Secret `api-db`. |
| Job em `ImagePullBackOff` | Falta o `ghcr-pull`, ou a tag `migrate-image` ainda é o placeholder inexistente. |

## Veja também
- [Postgres](../servicos/postgres.md) · [Publicar a API](publicar-a-api.md) · [CI/CD](ci-cd.md)
