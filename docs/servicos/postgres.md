# Postgres compartilhado

> **Resumo:** um único servidor Postgres 17 que guarda os bancos de todas as aplicações. Cada aplicação tem o seu banco e o seu usuário.
> **Para quem:** quem instala o Postgres (parte 1) e quem desenvolve uma aplicação (parte 2). **Dificuldade:** intermediária.
> **Palavras-chave:** postgres, banco de dados, new-database.sh, DATABASE_URL, postgres-credentials, pg, pgx, pg_dump, backup, conexões.

## O que é e onde fica
- Namespace `postgres`; StatefulSet com disco de 10 Gi (`local-path`) e o `postgres_exporter` (métricas) ao lado.
- Endereço, **só dentro do cluster**: `postgres.postgres.svc.cluster.local:5432`.
- A Application `postgres` é **manual** (precisa do Secret antes). Código: `gitops/groups/infra/postgres.yaml` e `gitops/manifests/postgres/`.

## Parte 1: instalar (operação)

**1. Criar o Secret do superusuário** (na VPS; nada vai ao Git):
```bash
ssh -t ubuntu@100.95.76.83
sudo k3s kubectl create namespace postgres
PW=$(openssl rand -hex 24)
sudo k3s kubectl -n postgres create secret generic postgres-credentials \
  --from-literal=POSTGRES_USER=postgres --from-literal=POSTGRES_PASSWORD="$PW" --from-literal=POSTGRES_DB=postgres
unset PW
```
**2.** No ArgoCD, clique em **Sync** na Application `postgres`.

**Como saber que deu certo:** `sudo k3s kubectl -n postgres get pods,pvc` mostra `postgres-0` `Running` e o volume `Bound`.

## Parte 2: criar o banco de uma aplicação
O script cria o usuário e o banco (mesmo nome), tira o acesso dos outros usuários a esse banco e grava o `DATABASE_URL` num Secret na namespace da aplicação. A senha é aleatória e **não é impressa**. Rode da raiz do repositório:
```bash
# uso: new-database.sh <banco> <namespace> [nome-do-secret]
ssh ubuntu@100.95.76.83 'bash -s -- api api api-db' < templates/postgres/new-database.sh
```
Se o banco já existir, o script aborta sem alterar nada. Para listar os bancos: `\l` no `psql`.

## Parte 3: usar na aplicação
O Secret (`api-db`, por exemplo) traz `DATABASE_URL`, no formato `postgres://<app>:<senha>@postgres.postgres.svc.cluster.local:5432/<app>?sslmode=disable`. O `sslmode=disable` é de propósito: o tráfego não sai do cluster.

Node (`pg`):
```js
import pg from 'pg';
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const { rows } = await pool.query('select current_user, current_database()');
```
Go (`pgx`):
```go
pool, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
```
- O usuário é dono só do banco dele; os outros bancos negam a conexão.
- É **uma instância** para todas as apps: o Postgres aceita 100 conexões no total por padrão, então mantenha o pool pequeno.
- O usuário pode criar tabelas. Para alterações de estrutura use [migrações](../aplicacoes/migracoes-do-banco.md).

## Operação do dia a dia
- **Entrar como administrador:** `sudo k3s kubectl -n postgres exec -it postgres-0 -c postgres -- psql -U postgres`. Dentro do pod o socket local não pede senha; de outros pods a senha é exigida.
- **Sem backup automático.** Os dados ficam no disco da VPS. Para algo além de testes, faça `pg_dump` periódico para fora da máquina.
- **Métricas e logs:** o job `postgres` do Prometheus e o Alloy já olham essa namespace. O dashboard *PostgreSQL* (14114) já vem no Grafana.

## Se der errado
| Sintoma | Causa provável |
|---|---|
| Pod em `CreateContainerConfigError` | Falta o Secret `postgres-credentials` (parte 1). |
| `permission denied for database` | Conectando no banco de outra aplicação. |
| `password authentication failed` | Usuário ou senha errados; releia o Secret. |

## Veja também
- [Migrações do banco](../aplicacoes/migracoes-do-banco.md) · [Checklist de uma aplicação nova](../aplicacoes/checklist-nova-aplicacao.md) · [Solução de problemas](../suporte/solucao-de-problemas.md)
