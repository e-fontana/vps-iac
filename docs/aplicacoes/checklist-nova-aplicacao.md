# Checklist: publicar uma aplicação nova

> **Resumo:** a lista de passos, na ordem, para colocar uma aplicação no cluster usando o banco, o Redis e o S3 compartilhados.
> **Para quem:** quem vai publicar uma aplicação (a API já existente ou uma nova). **Dificuldade:** intermediária.
> **Palavras-chave:** checklist, nova aplicação, passo a passo, secrets, new-database.sh, new-user.sh, new-bucket.sh, manifests, application, dns, ci.

Troque `meuapp` pelo nome da sua aplicação (minúsculas, números e `_`, começando por letra). **Rode da raiz do repositório** (`cloud`), com a VPN ligada.

> **Regra de ouro:** crie **todos os Secrets antes do primeiro Sync**. Sem eles o pod fica em `CreateContainerConfigError` (nada quebra, só espera).

## Passos

1. **Banco** (cria o banco, o usuário e o Secret `meuapp-db` na namespace `meuapp`):
   ```bash
   ssh ubuntu@100.95.76.83 'bash -s -- meuapp meuapp meuapp-db' < templates/postgres/new-database.sh
   ```
2. **Redis** (se usar; cria o usuário e o Secret `meuapp-redis`):
   ```bash
   ssh ubuntu@100.95.76.83 'bash -s -- meuapp meuapp meuapp-redis' < templates/redis/new-user.sh
   ```
3. **S3** (se usar; cria o bucket, uma chave só dele e o Secret `meuapp-s3`):
   ```bash
   ssh ubuntu@100.95.76.83 'bash -s -- meuapp meuapp meuapp-s3' < templates/seaweedfs/new-bucket.sh
   ```
4. **Imagem privada** (se o repositório da aplicação é privado): crie o Secret `ghcr-pull`. Veja [Imagem privada e tokens](imagem-privada-e-tokens.md).
5. **Manifests:** copie `gitops/manifests/api` para `gitops/manifests/meuapp`, ajuste os nomes e, no Deployment, aponte os Secrets: `envFrom: [{secretRef: {name: meuapp-db}}, {secretRef: {name: meuapp-redis}}, {secretRef: {name: meuapp-s3}}]`.
6. **Application do ArgoCD:** copie `gitops/groups/workloads/api.yaml` para `gitops/groups/workloads/meuapp.yaml` e ajuste `name`, `path` e `destination.namespace`. Ela começa **sem sync automático**; clique em *Sync* quando os Secrets existirem.
7. **DNS** (se tiver Ingress): registro `A` `meuapp` apontando para `100.95.76.83` na Cloudflare, com o proxy desligado. Veja [Expor com domínio](expor-com-dominio.md).
8. **Código e CI** (no repositório da aplicação): Dockerfile, workflows e o `GITOPS_TOKEN`. Veja [CI/CD](ci-cd.md). A imagem precisa ser `linux/arm64`: a VPS é ARM.
9. **Migrações** (se a aplicação usa Prisma): veja [Migrações do banco](migracoes-do-banco.md).

Para o caso concreto da API, com a tabela dos quatro Secrets: [Publicar a API](publicar-a-api.md).

## Como usar cada serviço no código
- [Postgres](../servicos/postgres.md) · [Redis](../servicos/redis.md) · [S3](../servicos/armazenamento-s3.md) · [Telemetria](../observabilidade/logs-traces-e-metricas.md)

## Como saber que deu certo
```bash
ssh ubuntu@100.95.76.83 'sudo k3s kubectl -n meuapp get secrets,pods'
```
Os Secrets existem e os pods ficam `Running`.

## Se der errado
Consulte a [Solução de problemas](../suporte/solucao-de-problemas.md). O erro mais comum é `secret "..." not found`: crie o Secret que faltou e o pod sobe sozinho (se não subir: `sudo k3s kubectl -n meuapp rollout restart deploy/meuapp`).
