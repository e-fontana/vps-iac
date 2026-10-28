# Usando a infra nas aplicações

Guia para quem desenvolve uma aplicação que roda neste cluster: o que a infra oferece, como pedir acesso e como
ligar cada serviço no código. A operação da infra (instalação, ordem de deploy, manutenção) está em
[gitops/README.md](../gitops/README.md).

Tudo aqui vale **dentro do cluster** e só é alcançável de fora **pela VPN** (Tailscale). Nada é publicado na internet.

> **O que foi testado:** os exemplos de código e os scripts foram executados contra o Postgres, o Redis e o SeaweedFS
> rodando em Docker, com as mesmas imagens e configurações do cluster, usando os Secrets gerados pelos scripts deste
> repositório. As versões foram: `ioredis` 6.0.0, `pg` 8.23.1, `@aws-sdk/client-s3` 3.1158.0, `pgx` 5.11.0, `go-redis` 9.23.0 e
> `aws-sdk-go-v2` 1.47.5 (`service/s3` 1.114.6). **Não** foram testados dentro do cluster, e o código de telemetria (OTLP) e as
> bibliotecas que não citei aqui (por exemplo filas sobre Redis) não foram exercitados.

## Visão geral

| Serviço | Endereço (dentro do cluster) | Como você pede acesso | O que você recebe |
|---|---|---|---|
| **Postgres** | `postgres.postgres.svc.cluster.local:5432` | [new-database.sh](../templates/postgres/new-database.sh) | Secret com `DATABASE_URL` |
| **Redis** | `redis.redis.svc.cluster.local:6379` | [new-user.sh](../templates/redis/new-user.sh) | Secret com `REDIS_URL`, `REDIS_USERNAME`, `REDIS_PASSWORD`, `REDIS_KEY_PREFIX` |
| **S3** (SeaweedFS) | `http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333` | manual, veja [S3](#s3-seaweedfs) | chave de acesso e segredo |
| **Telemetria** (OTLP) | `http://alloy.monitoring.svc.cluster.local:4318` (HTTP) ou `:4317` (gRPC) | nenhum pedido | variáveis `OTEL_*` |
| **HTTPS para a sua API** | `https://<app>.eduardofontana.dev` | Ingress + registro DNS, veja [Expor a API](#expor-a-api) | certificado automático |

Regras que valem para todos:
- **Um banco, um usuário Redis e um bucket por aplicação.** Nada de compartilhar credenciais entre apps.
- **Credenciais nunca vão para o Git.** Os scripts criam Secrets direto no cluster, com senhas aleatórias que não aparecem na tela.
- **Os Secrets ficam na namespace da aplicação** e entram no pod por `envFrom`, como variáveis de ambiente.

## Checklist: uma aplicação nova

Troque `meuapp` pelo nome da sua aplicação (minúsculas, números e `_`, começando por letra). Rode da raiz do repositório.

1. **Banco** (cria o banco, o usuário e o Secret `meuapp-db` na namespace `meuapp`):
   ```bash
   ssh ubuntu@100.95.76.83 'bash -s -- meuapp meuapp meuapp-db' < templates/postgres/new-database.sh
   ```
2. **Redis** (se usar; cria o usuário e o Secret `meuapp-redis`):
   ```bash
   ssh ubuntu@100.95.76.83 'bash -s -- meuapp meuapp meuapp-redis' < templates/redis/new-user.sh
   ```
3. **S3** (se usar): siga a seção [S3](#s3-seaweedfs).
4. **Manifests:** copie [gitops/manifests/api](../gitops/manifests/api) para `gitops/manifests/meuapp`, ajuste os nomes e, no
   Deployment, aponte os Secrets: `envFrom: [{secretRef: {name: meuapp-db}}, {secretRef: {name: meuapp-redis}}]`.
5. **Application do ArgoCD:** copie [gitops/groups/workloads/api.yaml](../gitops/groups/workloads/api.yaml) para
   `gitops/groups/workloads/meuapp.yaml` e ajuste `name`, `path` e `destination.namespace`. Ele começa **sem sync
   automático** (veja o comentário no arquivo); clique em Sync quando os Secrets existirem.
6. **DNS** (se tiver Ingress): registro `A` `meuapp` apontando para o IP da VPS na tailnet, com o proxy da Cloudflare desligado.
7. **CI:** [templates/api/github-actions.yml](../templates/api/github-actions.yml) e os Dockerfiles em [templates/api](../templates/api)
   (Go ou NestJS). A imagem precisa ser `linux/arm64`: a VPS é ARM.

**Crie os Secrets antes do primeiro Sync.** Sem eles o pod fica em `CreateContainerConfigError` (nada quebra, só espera).

## Postgres

O Secret traz `DATABASE_URL`, no formato `postgres://<app>:<senha>@postgres.postgres.svc.cluster.local:5432/<app>?sslmode=disable`.
O `sslmode=disable` é de propósito: o tráfego não sai do cluster.

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
- **Migrações:** rode no start da aplicação ou em um Job; o usuário é dono do banco e pode criar tabelas.
- **Sem backup automático**: os dados ficam no disco da VPS.

## Redis

O Secret traz `REDIS_URL` (`redis://<app>:<senha>@redis.redis.svc.cluster.local:6379`), `REDIS_USERNAME`, `REDIS_PASSWORD`
e `REDIS_KEY_PREFIX` (`<app>:`).

**Regra principal: toda chave e todo canal pub/sub começam com o prefixo `<app>:`.** O usuário só acessa `<app>:*`; fora
disso o Redis responde `NOPERM`.

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

- **Não roda** comandos administrativos ou perigosos (`FLUSHALL`, `CONFIG`, `KEYS`, `RANDOMKEY`, `DBSIZE`). Bibliotecas que dependem
  deles falham com `NOPERM`; use `SCAN` no lugar de `KEYS`.
- **Limitação:** o `SCAN` lista os **nomes** das chaves de todas as apps (os valores não vazam). A ACL evita colisões e
  acidentes entre as suas apps, não isola terceiros.
- **Memória:** o Redis tem 512 MB no total, com política `noeviction`: ao encher, as **escritas falham** em vez de descartar
  chaves. Dê TTL às chaves de cache.
- **Sem backup:** a persistência (AOF) está no disco da VPS.

## S3 (SeaweedFS)

Endereço: `http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`, **sem TLS e com endereçamento por caminho** (path-style:
`/<bucket>/<chave>`). A região pode ser qualquer uma (`us-east-1`). Cada identidade só enxerga o próprio bucket.

Node (AWS SDK v3):
```js
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
const s3 = new S3Client({
  endpoint: 'http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333',
  region: 'us-east-1',
  forcePathStyle: true,
  // credenciais: AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY do ambiente
});
await s3.send(new PutObjectCommand({ Bucket: 'meuapp', Key: 'pasta/arquivo.txt', Body: 'conteúdo' }));
```

Go (AWS SDK v2):
```go
cfg, _ := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1")) // credenciais: variáveis AWS_*
client := s3.NewFromConfig(cfg, func(o *s3.Options) {
	o.BaseEndpoint = aws.String("http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333")
	o.UsePathStyle = true
})
```

**Como conseguir um bucket e uma chave.** Hoje **não há script** para isso (só o bucket `observability-local`, do Loki e do
Tempo, é criado automaticamente). O procedimento manual, na VPS, é:
1. Gere uma chave e um segredo aleatórios (`openssl rand -hex 8` e `openssl rand -hex 24`).
2. Edite o JSON do Secret `seaweedfs-s3-config` (namespace `seaweedfs`) e acrescente uma identidade com
   `"actions": ["Read:meuapp", "Write:meuapp", "List:meuapp", "Tagging:meuapp"]`.
3. Crie o bucket com a identidade `admin` (`PUT /meuapp`, assinado com a chave do Secret `seaweedfs-admin`).
4. Reinicie o `seaweedfs-0`: `sudo k3s kubectl -n seaweedfs rollout restart statefulset/seaweedfs`. O Loki e o Tempo ficam
   alguns instantes sem o S3 durante o reinício.
5. Guarde a chave num Secret na namespace da aplicação (`AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY`).

Um sanity check do seu PC, pela VPN e com túnel, está no [gitops/README.md](../gitops/README.md#armazenamento-de-objetos-seaweedfs).
Sem backup e sem replicação: é um nó só.

## Telemetria (OpenTelemetry)

A aplicação exporta traces, métricas e logs por OTLP para o Alloy, que entrega ao Tempo, ao Prometheus e ao Loki. O
Deployment do [manifest da API](../gitops/manifests/api/api.yaml) já define as variáveis padrão do SDK:

| Variável | Valor |
|---|---|
| `OTEL_SERVICE_NAME` | o nome da app |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://alloy.monitoring.svc.cluster.local:4318` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` |

- Use o SDK do OpenTelemetry da linguagem; ele lê essas variáveis.
- **Logs em JSON no stdout, com `trace_id`:** é o que liga o log ao trace no Grafana.
- **Spans de banco:** instrumente o driver (`otelpgx` em Go, a instrumentação `pg` no Node).
- Para ligar o **log do Postgres** ao trace, use `sqlcommenter` (o `traceparent` como comentário no SQL).
- Onde olhar: Grafana (`https://grafana.eduardofontana.dev`), **Explore** com os datasources Tempo e Loki. Detalhes em
  [gitops/README.md](../gitops/README.md#logs-traces-e-métricas-da-api-opentelemetry).

## Expor a API

O Ingress usa o Traefik (`ingressClassName: traefik`) e o cert-manager emite o certificado (anotação
`cert-manager.io/cluster-issuer: letsencrypt`, `tls` com um `secretName`). Use o
[ingress.yaml da API](../gitops/manifests/api/ingress.yaml) como modelo, troque o `host` e crie o registro DNS `A`. O certificado
leva de 1 a 2 minutos; só funciona pela VPN.

## Quando algo falha

| Sintoma | Causa provável |
|---|---|
| Pod em `CreateContainerConfigError` | O Secret referenciado não existe ainda (passos 1 a 3 do checklist) |
| Redis: `NOPERM No permissions to access a key` | Chave sem o prefixo `<app>:` |
| Redis: `NOPERM ... run the '<comando>' command` | Comando administrativo ou perigoso, bloqueado de propósito |
| Redis: `WRONGPASS` / `NOAUTH` | Senha errada ou conexão sem a URL do Secret |
| Redis: escrita falha com `OOM` | Memória cheia (`noeviction`): apague chaves ou use TTL |
| Postgres: `permission denied for database` | Conectando no banco de outra aplicação |
| Postgres: `password authentication failed` | Senha ou usuário errados; releia o Secret |
| S3: `403` / `AccessDenied` | Bucket de outra identidade, ou a identidade ainda não foi criada |
| S3: `InvalidBucketName`, erro de DNS ou `NoSuchBucket` | Faltou `forcePathStyle` (o SDK tenta `<bucket>.<host>`), ou o bucket não foi criado |
| Imagem `exec format error` | Imagem `amd64`; a VPS é `arm64` |
