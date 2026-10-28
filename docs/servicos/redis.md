# Redis compartilhado

> **Resumo:** um único Redis 8 (banco em memória, bom para cache e filas) usado por várias aplicações. Cada aplicação tem o seu usuário, que só enxerga as chaves que começam com `<app>:`.
> **Para quem:** quem instala o Redis (parte 1) e quem desenvolve uma aplicação (parte 3). **Dificuldade:** intermediária.
> **Palavras-chave:** redis, cache, fila, acl, new-user.sh, create-secret.sh, redis-credentials, REDIS_URL, keyPrefix, NOPERM, noeviction, ioredis, go-redis.

## O que é e onde fica
- Namespace `redis`; StatefulSet, 1 réplica, persistência AOF em disco de 5 Gi (`local-path`), com o `redis_exporter` ao lado.
- Endereço, **só dentro do cluster**: `redis.redis.svc.cluster.local:6379`.
- A Application é **automática**: o Secret precisa existir **antes do `git push`**. Código: `gitops/groups/infra/redis.yaml` e `gitops/manifests/redis/`.

## Parte 1: instalar
**Rode o script ANTES do `git push`** (sem o Secret, o pod fica em `CreateContainerConfigError`):
```bash
ssh ubuntu@100.95.76.83 'bash -s' < templates/redis/create-secret.sh
```
Ele gera a senha do administrador (aleatória, nunca impressa) e cria `redis/redis-credentials`. Se já existir, aborta sem alterar nada.

**Como saber que deu certo:** depois do push, `sudo k3s kubectl -n redis get pods,pvc` mostra `redis-0` com 2/2 contêineres `Running` e o volume `Bound`.

## Parte 2: criar o usuário de uma aplicação
```bash
# uso: new-user.sh <app> <namespace> [nome-do-secret]
ssh ubuntu@100.95.76.83 'bash -s -- api api api-redis' < templates/redis/new-user.sh
```
Cria o usuário `api`, que só acessa chaves e canais `api:*`, e grava um Secret na namespace da aplicação com `REDIS_URL`, `REDIS_USERNAME`, `REDIS_PASSWORD` e `REDIS_KEY_PREFIX`. O usuário fica em `/data/users.acl` e sobrevive a reinícios. Se já existir, o script aborta.

## Parte 3: usar na aplicação
**Regra principal: toda chave e todo canal pub/sub começam com o prefixo `<app>:`.** Fora disso o Redis responde `NOPERM`.

Node (`ioredis`, que aplica o prefixo sozinho):
```js
import Redis from 'ioredis';
const redis = new Redis(process.env.REDIS_URL, { keyPrefix: process.env.REDIS_KEY_PREFIX });
await redis.set('sessao:1', 'valor'); // grava a chave "<app>:sessao:1"
```
Go (`go-redis` não tem opção de prefixo: prefixe você mesmo):
```go
opt, _ := redis.ParseURL(os.Getenv("REDIS_URL"))
rdb := redis.NewClient(opt)
rdb.Set(ctx, os.Getenv("REDIS_KEY_PREFIX")+"sessao:1", "valor", 0)
```
- **Não roda** comandos administrativos ou perigosos (`FLUSHALL`, `CONFIG`, `KEYS`, `RANDOMKEY`, `DBSIZE`). Bibliotecas que dependem deles falham com `NOPERM`; use `SCAN` no lugar de `KEYS`.
- **Memória:** 512 MB no total com política `noeviction`: ao encher, as **escritas falham** em vez de descartar chaves. Dê TTL (prazo de validade) às chaves de cache.

## O que a ACL isola e o que não isola
Testado com um Redis de verdade: o usuário de uma app **não** lê nem escreve chaves e canais de outro prefixo, e não roda `FLUSHALL`, `CONFIG`, `KEYS`, `RANDOMKEY` nem `DBSIZE`. Mas o `SCAN` continua liberado e **lista os nomes das chaves de todos os usuários** (os valores não vazam). Serve para evitar colisões e acidentes entre as suas aplicações, não para isolar terceiros. Para bloquear: `ACL SETUSER <app> -scan` e `ACL SAVE`.

## Operação do dia a dia
- **Memória:** `maxmemory 512mb`, limite do contêiner 1 Gi. Se for só cache, troque a política por `allkeys-lru` em `gitops/manifests/redis/redis.yaml`.
- **Entrar como administrador:** `sudo k3s kubectl -n redis exec -it redis-0 -c redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD"'`.
- **Trocar a senha do admin:** apague o Secret, rode o script de novo e `sudo k3s kubectl -n redis rollout restart statefulset/redis` (os usuários das apps são mantidos).
- **Sem backup:** os dados (AOF e ACLs) ficam no disco da VPS.
- **Observabilidade:** o job `redis` do Prometheus coleta o exporter (`redis_up` fica `0` se a senha estiver errada); o dashboard *Redis* (763) já vem no Grafana.
- Os termos de licença do Redis 8 não foram analisados; o Valkey é o fork BSD, se isso importar.

## Se der errado
| Sintoma | Causa provável |
|---|---|
| `NOPERM No permissions to access a key` | Chave sem o prefixo `<app>:`. |
| `NOPERM ... run the '<comando>' command` | Comando administrativo bloqueado de propósito. |
| `WRONGPASS` / `NOAUTH` | Senha errada, ou conexão sem a URL do Secret. |
| Escrita falha com `OOM` | Memória cheia: apague chaves ou use TTL. |

## Veja também
- [Checklist de uma aplicação nova](../aplicacoes/checklist-nova-aplicacao.md) · [Solução de problemas](../suporte/solucao-de-problemas.md)
