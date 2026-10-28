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
| **S3** (SeaweedFS) | `http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333` | [new-bucket.sh](../templates/seaweedfs/new-bucket.sh) | Secret com `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION` |
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
3. **S3** (se usar; cria o bucket, uma chave só dele e o Secret `meuapp-s3`):
   ```bash
   ssh ubuntu@100.95.76.83 'bash -s -- meuapp meuapp meuapp-s3' < templates/seaweedfs/new-bucket.sh
   ```
4. **Manifests:** copie [gitops/manifests/api](../gitops/manifests/api) para `gitops/manifests/meuapp`, ajuste os nomes e, no
   Deployment, aponte os Secrets: `envFrom: [{secretRef: {name: meuapp-db}}, {secretRef: {name: meuapp-redis}}, {secretRef: {name: meuapp-s3}}]`.
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
- **Migrações:** o usuário é dono do banco e pode criar tabelas. O padrão é um Job que roda antes de cada deploy, veja [Migrações do banco](#migrações-do-banco).
- **Sem backup automático**: os dados ficam no disco da VPS.

## Migrações do banco

Para uma aplicação com migrações (a API usa Prisma), o padrão é um **Job do ArgoCD no hook `PreSync`**, que roda e termina com
sucesso **antes** de o ArgoCD atualizar o Deployment: [migrate-job.yaml](../gitops/manifests/api/migrate-job.yaml).

- **Imagem separada.** A imagem final da aplicação é podada (`pnpm prune --prod`) e não tem o CLI do Prisma nem a pasta
  `prisma/`, então não consegue migrar. O `Dockerfile` da API tem um alvo `migrate` (`docker build --target migrate`) com as duas
  coisas, e o CI publica as duas imagens (`api` e `api-migrate`) e atualiza as duas tags (`api-image` e `migrate-image`) no
  [kustomization.yaml](../gitops/manifests/api/kustomization.yaml).
- **Sem migrações pendentes, o Job não faz nada** (`No pending migrations to apply`), então ele roda em todo deploy sem custo.
- **Se a migração falhar, o deploy para:** o `PreSync` falha e a versão antiga da API continua no ar. Veja o motivo com
  `kubectl -n api logs job/api-migrate` (o último Job fica no cluster e é recriado no deploy seguinte).
- **Compatibilidade:** a migração roda antes de a versão nova subir, então ela precisa ser compatível com a versão antiga da
  aplicação (adicione colunas e tabelas primeiro, remova só num deploy posterior).
- **Pré-requisitos:** a namespace `api` e o Secret `api-db` já existem (`templates/postgres/new-database.sh`), porque o `PreSync` roda
  antes do resto da Application.
- **Enquanto o kustomization aponta o placeholder** (`busybox`), o Job termina na hora e não migra nada; serve para testar a
  infra com a imagem de teste da API.

Testado: a imagem `migrate` (amd64) aplicou as 2 migrações da API num Postgres vazio em 2 segundos, como usuário não root, e a
segunda execução não fez nada. **Não** foi testado: o build em `arm64` (a VPS é ARM; o motor de migração do Prisma é um binário por
arquitetura, baixado durante o build) nem a execução como hook dentro do cluster.

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

O Secret traz `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (as chaves padrão do SDK da AWS, lidas sozinhas do ambiente),
`S3_ENDPOINT` (`http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333`), `S3_BUCKET` e `S3_REGION` (`us-east-1`).

Dois detalhes do endereço: **sem TLS** e **com endereçamento por caminho** (path-style: `/<bucket>/<chave>`, por isso o
`forcePathStyle`). Cada identidade só lê, grava, lista e apaga no **próprio bucket**: não cria buckets nem enxerga os dos outros.

Node (AWS SDK v3):
```js
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
const s3 = new S3Client({
  endpoint: process.env.S3_ENDPOINT,
  region: process.env.S3_REGION,
  forcePathStyle: true,
  // credenciais: AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY do ambiente
});
await s3.send(new PutObjectCommand({ Bucket: process.env.S3_BUCKET, Key: 'pasta/arquivo.txt', Body: 'conteúdo' }));
```

Go (AWS SDK v2):
```go
cfg, _ := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1")) // credenciais: variáveis AWS_*
client := s3.NewFromConfig(cfg, func(o *s3.Options) {
	o.BaseEndpoint = aws.String(os.Getenv("S3_ENDPOINT"))
	o.UsePathStyle = true
})
```

**Armadilha com OpenTelemetry (assinatura SigV4):** se a aplicação acrescenta um cabeçalho à requisição ao S3 **antes** de
assinar (por exemplo o `traceparent`, no passo `build` do SDK) e a instrumentação `http` do OpenTelemetry o **reescreve** ao enviar,
a assinatura deixa de bater e o S3 responde **403**. O SDK mostra só `UnknownError`, porque um `HEAD` não tem corpo. Foi o que
travou o `readiness` da API (503 em `storage`). Registre o cabeçalho **depois** da assinatura (`step: 'finalizeRequest'`, `priority: 'low'`):
ele continua sendo enviado, só que fora dos `SignedHeaders`. Verificado com a API contra o SeaweedFS.

**Como conseguir um bucket e uma chave:** o script [new-bucket.sh](../templates/seaweedfs/new-bucket.sh) (passo 3 do checklist).
- A chave **vale na hora**, sem reiniciar nada, e o Loki e o Tempo não são afetados.
- Se o bucket ou a identidade já existir, o script aborta sem alterar nada. Se algo falhar no meio, ele desfaz o que criou.
- Os nomes `admin`, `loki`, `tempo` e `observability-local` são reservados.
- As chaves geradas ficam no Secret da aplicação **e** no volume do SeaweedFS (é de lá que ele as lê). Para remover uma
  identidade e o bucket, veja o cabeçalho do script; apagar o bucket apaga os objetos.

Sanity check do seu PC, pela VPN e com túnel: [gitops/README.md](../gitops/README.md#armazenamento-de-objetos-seaweedfs).
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

## Imagem privada e tokens do CI

Se o repositório da aplicação é privado, a imagem no GHCR também é (pacotes novos nascem privados). São **dois tokens
diferentes**, em lugares diferentes:

| Token | Para quê | Onde fica | Tipo |
|---|---|---|---|
| `GITOPS_TOKEN` | o CI da aplicação gravar a tag nova da imagem no `vpn-iac` | secret do GitHub Actions do repositório **da aplicação** | *fine-grained*, só o repositório `vpn-iac`, permissão **Contents: Read and write** |
| token de pull | a VPS baixar a imagem privada | Secret do Kubernetes `ghcr-pull`, na namespace da app | **classic**, só o escopo `read:packages` (o GHCR não aceita *fine-grained*) |

O ArgoCD não precisa de token nenhum: o `vpn-iac` é público e ele nunca clona o repositório da aplicação.

**`GITOPS_TOKEN`** (os caminhos de menu do GitHub podem mudar):
1. GitHub, foto do perfil, **Settings**, **Developer settings**, **Personal access tokens**, **Fine-grained tokens**, **Generate new token**.
2. Em *Repository access*, escolha **Only select repositories** e marque `vpn-iac`. Em *Repository permissions*, **Contents: Read and write**.
3. Defina a validade (quando o token expirar, o CI falha na hora de gravar a tag) e gere.
4. No repositório da aplicação: **Settings**, **Secrets and variables**, **Actions**, **New repository secret**, nome `GITOPS_TOKEN`.
5. Se a branch `main` do `vpn-iac` tiver proteção, o `push` do CI será recusado.

**Pull da imagem (`imagePullSecret`):**
1. Gere um token **classic** só com `read:packages`: <https://github.com/settings/tokens/new?scopes=read:packages>.
2. Da raiz deste repositório, rode (ele pede o usuário e o token sem eco, e o token não vira argumento nem aparece na tela):
   ```bash
   KUBECTL="ssh ubuntu@100.95.76.83 sudo k3s kubectl" bash templates/api/create-pull-secret.sh meuapp ghcr-pull
   ```
3. O [manifest da API](../gitops/manifests/api/api.yaml) já referencia o Secret (`imagePullSecrets: [{name: ghcr-pull}]`).
4. Para trocar um token expirado, rode o mesmo comando de novo: ele atualiza o Secret.

Alternativa sem token de pull: tornar o pacote público (a página do pacote no GitHub, **Package settings**, **Change visibility**).
O preço é que as camadas da imagem, com o código compilado da aplicação, ficam públicas.

O script foi testado contra um registry privado local com senha (o `docker pull` com o Secret gerado funcionou, e com token
errado ou sem credencial foi recusado). Não foi testado contra o GHCR de verdade nem no cluster.

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
| S3: `UnknownError` (um `HEAD` com 403) só com o OpenTelemetry ligado | Cabeçalho assinado e depois reescrito pela instrumentação `http`: veja a armadilha na seção S3 |
| S3: `InvalidBucketName`, erro de DNS ou `NoSuchBucket` | Faltou `forcePathStyle` (o SDK tenta `<bucket>.<host>`), ou o bucket não foi criado |
| Imagem `exec format error` | Imagem `amd64`; a VPS é `arm64` |
