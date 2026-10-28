# GitOps

Este arquivo é a visão de **operação** da infra. Para quem desenvolve aplicações (como usar o Postgres, o Redis, o S3 e a
telemetria, com exemplos de código): [docs/usando-a-infra.md](../docs/usando-a-infra.md).

```
gitops/
├── apps/                     # o root lê só aqui: projetos + uma Application por grupo
│   ├── projects.yaml         # AppProjects (groups, networking, infra, observability, workloads)
│   ├── networking.yaml       # → groups/networking
│   ├── observability.yaml    # → groups/observability
│   ├── infra.yaml            # → groups/infra
│   └── workloads.yaml        # → groups/workloads
├── groups/
│   ├── networking/           # cert-manager, cert-manager-config, traefik, argocd-ingress, tailscale-operator
│   ├── observability/        # prometheus, loki, tempo, alloy, grafana
│   ├── infra/                # postgres, redis (compartilhados) e seaweedfs (S3 local)
│   └── workloads/            # api (aplicações próprias)
└── manifests/                # YAML simples usados pelas Applications (ClusterIssuer, Ingress)
```

A Application `root` (criada pelo bootstrap da VM) observa `gitops/apps`, definido por `gitops_path`
no tfvars. Cada grupo é uma Application que observa a própria pasta em `groups/`, então na interface
do ArgoCD os serviços aparecem agrupados: abra `networking` ou `observability` para ver os filhos,
ou filtre a lista por **Project**: `groups` mostra só os macros (`networking` e `observability`);
`networking` e `observability` mostram os serviços de cada área.

**Adicionar um serviço:** crie um YAML em `groups/<grupo>/` com `project: <grupo>` e o label
`group: <grupo>`, e faça push. **Novo grupo:** um `AppProject` em `apps/projects.yaml`, um arquivo
`apps/<grupo>.yaml` (com `project: groups`) copiado de um existente e uma pasta `groups/<grupo>/`.

Ordem de sync (ondas): projetos (-1), grupos `networking` (0), `infra` e `observability` (1) e `workloads` (2); dentro de cada
grupo, as ondas de cada Application.

## Tailscale operator: pré-requisitos

1. **ACL** (admin do Tailscale → Access controls), adicione em `tagOwners`:
   ```json
   "tagOwners": {
     "tag:k8s-operator": [],
     "tag:k8s": ["tag:k8s-operator"]
   }
   ```
2. **OAuth client** (Settings → OAuth clients → Generate): escopos
   `Devices Core: write` e `Auth Keys: write`, ambos com a tag `tag:k8s-operator`.
   Guarde o client id e o secret.
3. **HTTPS** habilitado em DNS (já exigido pelo certificado do ArgoCD).
4. **Secret no cluster** (via tailnet, fora do Git). A namespace precisa existir antes:
   ```bash
   kubectl create namespace tailscale
   kubectl -n tailscale create secret generic operator-oauth \
     --from-literal=client_id=<ID> \
     --from-literal=client_secret=<SECRET>
   ```
   Se quiser versionar a credencial, use Sealed Secrets ou SOPS em vez de texto puro.

Depois disso o ArgoCD sincroniza o operator. Confira com:
`kubectl -n tailscale get pods` e o dispositivo `tailscale-operator` no painel do Tailscale.

## Expondo um serviço na tailnet

HTTPS com certificado automático e nome próprio (`meu-servico.<tailnet>.ts.net`):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: meu-servico
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: meu-servico
      port:
        number: 80
  tls:
    - hosts:
        - meu-servico
```

TCP simples (sem HTTPS), anotando o próprio Service:
```yaml
metadata:
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "meu-servico"
```

## Ingress, certificados e observabilidade

`cert-manager` (certificados Let's Encrypt via Cloudflare DNS-01) + `traefik` (ingress na 443)
+ `prometheus` e `grafana`. Ficam em `groups/`, com ordem de sync por ondas.
Resultado: `https://argocd.eduardofontana.dev` e `https://grafana.eduardofontana.dev`, sem porta,
só pela VPN.

### Ordem da migração (importante)

**Não faça `git push` antes dos passos A e B.** O ArgoCD sincroniza sozinho: o Traefik tentaria
ocupar a porta 443, que hoje é do `argocd-server`, e o ClusterIssuer e o Grafana subiriam sem
os Secrets.

**A. Secrets (na VPS; nada vai ao Git)**
```bash
ssh -t ubuntu@100.95.76.83
sudo k3s kubectl create namespace cert-manager
sudo k3s kubectl create namespace monitoring

read -rsp 'Token da Cloudflare: ' CF; echo
sudo k3s kubectl -n cert-manager create secret generic cloudflare-api-token --from-literal=api-token="$CF"
unset CF

read -rsp 'Senha do admin do Grafana: ' GP; echo
sudo k3s kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$GP"
unset GP
```
O token pode ser o mesmo do certbot (*Edit zone DNS*, restrito à zona). Guarde a senha do Grafana
num gerenciador: o Secret `grafana-admin` é a única fonte dela.

**B. ArgoCD sai da 443 e passa a responder em HTTP (o TLS passa a ser do Traefik)**
```bash
sudo k3s kubectl -n argocd patch cm argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}'
sudo k3s kubectl -n argocd patch svc argocd-server --type json -p '[
  {"op":"replace","path":"/spec/type","value":"ClusterIP"},
  {"op":"remove","path":"/spec/ports/0/nodePort"},
  {"op":"remove","path":"/spec/ports/1/nodePort"}]'
sudo k3s kubectl -n argocd rollout restart deploy/argocd-server
sudo systemctl disable --now argocd-cert-renew.timer
```
A partir daqui a UI do ArgoCD fica fora do ar até o Traefik e o certificado subirem (alguns
minutos). Se precisar dela antes: `ssh -L 8080:localhost:8080 ubuntu@100.95.76.83` e, na VPS,
`sudo k3s kubectl -n argocd port-forward svc/argocd-server 8080:80`.

**C. DNS:** registro `A` `grafana` → `100.95.76.83`, proxy desligado (o `argocd` já existe).

**D. `git push`.** A Application `root` sincroniza as novas Applications em ondas. Acompanhe:
```bash
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl get certificate -A      # READY=True em ~1-2 min por certificado (DNS-01)
sudo k3s kubectl get pods -A
```

### Depois

- Grafana: usuário `admin` e a senha do passo A. O datasource Prometheus e os dashboards
  *Node Exporter Full* e *kube-state-metrics v2* já vêm provisionados.
- CLI do ArgoCD atrás do Traefik: `argocd login argocd.eduardofontana.dev --grpc-web`.
- Opcional: `sudo k3s kubectl -n argocd delete secret argocd-server-tls` (sobra do certbot).

### Notas

- O download dos dashboards roda no start do pod do Grafana e precisa de acesso ao grafana.com.
- Prometheus guarda 15 dias em PVC de 10 Gi (`local-path` do k3s). Não há backup desses dados.
- O `ingressEndpoint.ip` do Traefik é o IP da VPS na tailnet (`traefik.yaml`). Se ele mudar,
  atualize ali; é só cosmético (status dos Ingress).

## Postgres compartilhado (infra)

`groups/infra/postgres.yaml` aplica `manifests/postgres`: namespace `postgres`, um Postgres 17 (StatefulSet,
10 Gi em `local-path`) com o `postgres_exporter` ao lado. É **uma instância para vários bancos**: cada aplicação
tem o seu banco e o seu usuário. Fica em `postgres.postgres.svc.cluster.local:5432`, só dentro do cluster.
A Application está **sem sync automático** (o Secret precisa existir antes): veja o comentário no arquivo.

### 1. Secret do superusuário (na VPS; nada vai ao Git)
```bash
ssh -t ubuntu@100.95.76.83
sudo k3s kubectl create namespace postgres
PW=$(openssl rand -hex 24)
sudo k3s kubectl -n postgres create secret generic postgres-credentials \
  --from-literal=POSTGRES_USER=postgres --from-literal=POSTGRES_PASSWORD="$PW" --from-literal=POSTGRES_DB=postgres
unset PW
```
Depois clique em **Sync** na Application `postgres`. Confira: `sudo k3s kubectl -n postgres get pods,pvc`.

### 2. Criar o banco de uma aplicação
O script cria o usuário e o banco (mesmo nome), revoga o acesso dos outros usuários a esse banco e grava o
`DATABASE_URL` num Secret na namespace da aplicação. A senha é aleatória e não é impressa:
```bash
# uso: new-database.sh <banco> <namespace> [nome-do-secret]
ssh ubuntu@100.95.76.83 'bash -s -- api api api-env' < templates/postgres/new-database.sh
ssh ubuntu@100.95.76.83 'bash -s -- billing billing'  < templates/postgres/new-database.sh   # outro banco
```
Se o banco já existir, o script aborta sem alterar nada. Para listar: `\l` no `psql`.

### Operação
- Acesso de administração: `sudo k3s kubectl -n postgres exec -it postgres-0 -c postgres -- psql -U postgres`.
  Dentro do pod, o socket local não pede senha; de outros pods, a senha é exigida.
- **Sem backup automático**: os dados ficam no disco da VPS. Para algo além de testes, faça `pg_dump`
  periódico para fora da máquina.
- Métricas e logs: o job `postgres` do Prometheus e o Alloy já olham a namespace `postgres`.

## Armazenamento de objetos (SeaweedFS)

`groups/infra/seaweedfs.yaml` aplica `manifests/seaweedfs`: namespace `seaweedfs`, um SeaweedFS 4.51 em um processo
só (master, volume, filer e gateway S3), 1 réplica, 20 Gi em `local-path`. O S3 fica em
`http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333` (path-style, sem TLS), só dentro do cluster. Um Job (hook
PostSync) cria o bucket `observability-local`. É o armazenamento do Loki e do Tempo.

Cada serviço tem uma **identidade própria**, com permissão só no bucket dele (`Read:`, `Write:`, `List:`,
`Tagging:` por bucket): o Loki e o Tempo não enxergam outros buckets e não criam buckets.

### Ordem para ativar (importante)
**Rode o script ANTES do `git push`.** O Loki e o Tempo passam a depender do SeaweedFS e dos Secrets dele; sem os
Secrets, os pods ficam em `CreateContainerConfigError` e os logs e traces ficam sem armazenamento.
```bash
ssh ubuntu@100.95.76.83 'bash -s' < templates/seaweedfs/create-secrets.sh
```
O script gera as chaves (aleatórias, passam por stdin e não são impressas) e cria `seaweedfs-s3-config` e
`seaweedfs-admin` (namespace `seaweedfs`), `loki-s3` e `tempo-s3` (namespace `monitoring`). Se já existirem, aborta
sem alterar nada.

Depois do push (e do refresh do `root`), confira:
```bash
sudo k3s kubectl -n seaweedfs get pods,pvc                  # seaweedfs-0 Running
sudo k3s kubectl -n seaweedfs logs job/seaweedfs-create-bucket  # "bucket observability-local ok" (o Job some ao terminar)
sudo k3s kubectl -n monitoring get pods                     # loki-0 e tempo-0 Running, sem reiniciar em loop
```
Sem o bucket, o Loki e o Tempo **encerram na inicialização** (testei os dois contra um SeaweedFS sem o bucket) e
o Kubernetes os reinicia até ele existir. Como o bucket só é criado depois que o SeaweedFS fica saudável, no primeiro
deploy é normal ver `CrashLoopBackOff` neles por alguns minutos; some sozinho.

### Acessar o S3 do seu PC
Só pela VPN, com um túnel (não há Ingress de propósito):
```bash
ssh -L 8333:localhost:8333 ubuntu@100.95.76.83 'sudo k3s kubectl -n seaweedfs port-forward svc/seaweedfs-s3 8333:8333'
```
As chaves do admin estão no Secret `seaweedfs-admin`. O `aws` CLI ou o `curl --aws-sigv4` servem de cliente.

### Dados que já existiam no Loki e no Tempo
Trocar o armazenamento **não migra** nada: o que estiver nos volumes antigos deixa de ser lido. Como as fontes de
logs e traces (a API e o Postgres) ainda não rodam, o esperado é não haver nada a perder.

### Limites e riscos
- **Um nó, sem replicação e sem backup.** Os dados ficam no disco da VPS.
- **Disco:** volumes de 512 MB, até 40, com PVC de 20 Gi; os volumes viram somente leitura com menos de 5% livre.
- **Segurança:** o SeaweedFS avisa que o gRPC do filer (porta 18888, dentro do pod) aceita gerenciar usuários sem
  autenticação para quem o alcançar. Só o serviço do S3 (8333) é publicado, mas qualquer pod do cluster alcança o IP do
  pod. Uma `NetworkPolicy` limitando a entrada à porta 8333 resolveria; não está incluída porque não testei se o
  controlador de rede do k3s a aplica sem atrapalhar a comunicação interna do pod.
- O log do SeaweedFS mostra um erro de STS ("no signing key found"): ele se refere a tokens temporários, que não usamos,
  e não afetou as identidades estáticas nos testes.
- **Novos buckets e identidades:** `templates/seaweedfs/new-bucket.sh` (veja o guia das aplicações). Ele usa o `weed shell`
  dentro do pod: cria a identidade (escopo só no bucket), o bucket com ela como dona e o Secret na namespace da aplicação.
  Vale na hora, sem reiniciar. As identidades criadas assim ficam gravadas no volume do SeaweedFS (sobrevivem a reinícios), junto das
  estáticas do `s3.json` (marcadas `isStatic` no `s3.configure`), que continuam intactas. **Cuidado:** o comando
  `s3.configure` do `weed shell` imprime as chaves de todas as identidades em texto; não o rode em lugares que gravam a saída.

## Redis compartilhado (infra)

`groups/infra/redis.yaml` aplica `manifests/redis`: namespace `redis`, um Redis 8.10 (imagem alpine, StatefulSet), 1 réplica,
persistência AOF em 5 Gi de `local-path`, com o `redis_exporter` ao lado. É **uma instância para várias aplicações**: cada
uma tem o seu usuário (ACL), restrito às chaves com o prefixo `<app>:`. Fica em `redis.redis.svc.cluster.local:6379`, só
dentro do cluster. A Application é **automática**, então o Secret precisa existir antes do push.

### Ordem para ativar
**Rode o script ANTES do `git push`** (sem o Secret, o pod fica em `CreateContainerConfigError`):
```bash
ssh ubuntu@100.95.76.83 'bash -s' < templates/redis/create-secret.sh
```
Ele gera a senha do administrador (aleatória, via stdin, nunca impressa) e cria `redis/redis-credentials`; se já existir,
aborta sem alterar nada. Depois do push e do refresh do `root`: `sudo k3s kubectl -n redis get pods,pvc` (esperado:
`redis-0` com 2/2 contêineres `Running` e o volume `Bound`).

### Usuário de uma aplicação
```bash
# uso: new-user.sh <app> <namespace> [nome-do-secret]
ssh ubuntu@100.95.76.83 'bash -s -- api api api-redis' < templates/redis/new-user.sh
```
Cria o usuário `api`, que só acessa chaves e canais `api:*`, e grava um Secret na namespace da aplicação com `REDIS_URL`,
`REDIS_USERNAME`, `REDIS_PASSWORD` e `REDIS_KEY_PREFIX`. O usuário é gravado em `/data/users.acl` e sobrevive a
reinícios. Se já existir, o script aborta. **A aplicação precisa prefixar as chaves** com `REDIS_KEY_PREFIX` (por exemplo,
a opção `keyPrefix` do ioredis); sem o prefixo, o Redis responde `NOPERM`.

### O que a ACL isola e o que não isola
Testei com um Redis de verdade. O usuário de uma app **não** lê nem escreve chaves e canais de outro prefixo, e não roda
`FLUSHALL`, `CONFIG`, `KEYS`, `RANDOMKEY` nem `DBSIZE`. Mas o `SCAN` continua liberado (muitas apps dependem dele) e
**lista os nomes das chaves de todos os usuários**, não os valores. Serve para evitar colisões e acidentes entre as suas
aplicações, não para isolar terceiros. Para bloquear: `ACL SETUSER <app> -scan` e `ACL SAVE`.

### Operação
- **Memória:** `maxmemory 512mb` com política `noeviction`: nada é descartado em silêncio, e no limite as escritas falham.
  Se for só cache, troque por `allkeys-lru` em `manifests/redis/redis.yaml`. O limite do contêiner é 1 Gi.
- **Admin:** `sudo k3s kubectl -n redis exec -it redis-0 -c redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD"'`.
- **Trocar a senha do admin:** apague o Secret, rode o script de novo e `sudo k3s kubectl -n redis rollout restart statefulset/redis`
  (o start reescreve o usuário default a partir do Secret e mantém os usuários das apps).
- **Sem backup:** os dados (AOF e ACLs) ficam no disco da VPS.
- **Observabilidade:** o job `redis` do Prometheus coleta o exporter (`redis_up` fica `0` se a senha estiver errada), o
  dashboard *Redis Dashboard for Prometheus Redis Exporter* (763) já vem provisionado no Grafana e os logs vão para o Loki.
- Não analisei os termos de licença do Redis 8 (o GitHub não identifica uma licença única); o Valkey é o fork BSD, se isso importar.

## API própria (Go ou NestJS)

`groups/workloads/api.yaml` descreve `manifests/api` (hoje **sem sync automático**: a Application fica `OutOfSync`
até você mandar; veja o comentário no próprio arquivo). Ele cria: namespace `api`, a API (Deployment + Service) e
um Ingress em `https://api.eduardofontana.dev`, só pela VPN. O banco da API fica no **Postgres compartilhado**
(seção acima), que precisa estar no ar antes.
Até existir imagem própria, a API roda a imagem de teste `traefik/whoami`: serve para validar DNS,
TLS e ingress antes de escrever código.

### 1. Banco e Secret da API (na VPS; nada vai ao Git)
Com o Postgres compartilhado no ar, um comando cria o banco `api` e o Secret `api-env` (namespace `api`):
```bash
ssh ubuntu@100.95.76.83 'bash -s -- api api api-env' < templates/postgres/new-database.sh
```
`sslmode=disable` na URL porque o tráfego fica dentro do cluster. **Crie o Secret antes do Sync**, ou o pod
da API fica em `CreateContainerConfigError`.

### 2. DNS
Registro `A` `api` → IP da VPS na tailnet, proxy desligado.

### 3. Conferir a infra com a imagem de teste
```bash
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl -n api get pods,certificate
curl -s https://api.eduardofontana.dev/    # pela VPN: a imagem de teste devolve os headers da requisição
```

### 4. Colocar o código
No repositório da API (separado deste):
1. Copie `templates/api/Dockerfile.go` ou `Dockerfile.nest` como `Dockerfile`. A API deve ouvir em
   `0.0.0.0:8080` (variável `PORT`) e ler `DATABASE_URL` do ambiente.
2. Copie `templates/api/github-actions.yml` para `.github/workflows/deploy.yml` e crie o secret
   `GITOPS_TOKEN` (permissão de escrita só neste repositório de infra).
3. Imagem privada no GHCR: o cluster precisa de um `imagePullSecret` (ou deixe o pacote público).
4. A cada push na `main`, o CI publica a imagem `linux/arm64`, troca a tag no `kustomization.yaml` e o
   ArgoCD aplica. Migrações: rode no start da API ou em um Job.

- Redis: `bash -s -- api api api-redis` com `templates/redis/new-user.sh` cria o usuário e o Secret `api-redis` (seção acima).
- Métricas da API: descomente as anotações `prometheus.io/*` no Service em `manifests/api/api.yaml`.

## Logs, traces e métricas da API (OpenTelemetry)

Stack: **Alloy** (coletor) → **Loki** (logs), **Tempo** (traces) e **Prometheus** (métricas), tudo visto no
Grafana (`https://grafana.eduardofontana.dev`). **Loki e Tempo guardam os dados no SeaweedFS** (S3 local, bucket
`observability-local`: o Loki em `fake/` e `index/`, o Tempo em `tempo/`); o volume de 10 Gi de cada um guarda só o
WAL. Retenção de 7 dias em ambos. O Prometheus continua no disco (PVC de 10 Gi, 15 dias): ele não escreve em S3.
Nada disso foi testado com uma API de verdade.

```
API ──OTLP──► alloy:4318 ──► Tempo (traces) · Prometheus (métricas, via remote_write) · Loki (logs OTLP)
pods das namespaces "api", "postgres", "seaweedfs" e "redis" ──► Alloy (lê pela API do Kubernetes) ──► Loki
postgres_exporter (sidecar do Postgres) ──► Prometheus (job "postgres")
```

### O que a API precisa fazer
- **Exportar OTLP.** O Deployment já define `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`
  (`http://alloy.monitoring.svc.cluster.local:4318`) e `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`.
  Basta o SDK do OpenTelemetry da linguagem (Go ou Node) ler essas variáveis.
- **Logs em JSON no stdout, com `trace_id`.** O Alloy coleta o stdout dos pods das namespaces `api`, `postgres`, `seaweedfs` e `redis`, então os
  logs da API e do Postgres ficam no mesmo Loki (`{namespace=~"api|postgres"}`). No Loki, o campo `trace_id` do
  JSON vira um link para o trace no Tempo. (A API também pode mandar logs por OTLP; escolha um dos dois
  para não duplicar.)
- **Spans de banco.** Use a instrumentação do driver (`otelpgx` em Go, a instrumentação `pg` no Nest): as
  queries aparecem dentro do trace, no Tempo.

### Ligar o log do Postgres ao trace
O Postgres não fala OpenTelemetry. Sozinhos, o log dele e o trace da API só se relacionam por horário e pod.
Para ligar de verdade, a API deve usar **sqlcommenter**: colocar o `traceparent` como comentário no SQL. O
Postgres já loga statements acima de 250 ms (`log_min_duration_statement`) e esperas por lock, e a linha
carrega o comentário. No Loki, o campo derivado `traceparent` abre o trace no Tempo. No Tempo, o botão de
logs do span busca `{namespace=~"api|postgres"} |= "<traceId>"`.

### Métricas do banco
O sidecar `postgres_exporter` (porta 9187) é coletado pelo job `postgres` do Prometheus. O dashboard
*PostgreSQL Exporter Quickstart* (14114) já vem provisionado no Grafana. Ele só mostra dados depois que o
Postgres compartilhado estiver no ar.

### Conferir depois do deploy
```bash
sudo k3s kubectl -n monitoring get pods                     # loki, tempo, alloy Running
sudo k3s kubectl -n monitoring logs deploy/alloy --tail=30  # sem erros de envio
```
No Grafana: **Explore → Loki** com `{namespace=~"api|postgres"}`; **Explore → Tempo**; e **Connections → Data sources**
para ver Loki e Tempo.
