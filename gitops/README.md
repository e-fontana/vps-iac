# GitOps

```
gitops/
├── apps/                     # o root lê só aqui: projetos + uma Application por grupo
│   ├── projects.yaml         # AppProjects (groups, networking, observability, workloads)
│   ├── networking.yaml       # → groups/networking
│   ├── observability.yaml    # → groups/observability
│   └── workloads.yaml        # → groups/workloads
├── groups/
│   ├── networking/           # cert-manager, cert-manager-config, traefik, argocd-ingress, tailscale-operator
│   ├── observability/        # prometheus, loki, tempo, alloy, grafana
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

Ordem de sync (ondas): projetos (-1), grupos `networking` (0) e `observability` (1) e `workloads` (2); dentro de cada
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

## API própria (Go ou NestJS + Postgres)

`groups/workloads/api.yaml` descreve `manifests/api` (hoje **sem sync automático**: a Application fica `OutOfSync`
até você mandar; veja o comentário no próprio arquivo). Ele cria: namespace `api`, Postgres (StatefulSet, 5 Gi em
`local-path`), a API (Deployment + Service) e um Ingress em `https://api.eduardofontana.dev`, só pela VPN.
Até existir imagem própria, a API roda a imagem de teste `traefik/whoami`: serve para validar DNS,
TLS e ingress antes de escrever código.

### 1. Secrets (na VPS; nada vai ao Git)
```bash
ssh -t ubuntu@100.95.76.83
sudo k3s kubectl create namespace api

PW=$(openssl rand -hex 24)    # só letras e números: entra na URL do banco sem precisar de escape
sudo k3s kubectl -n api create secret generic postgres-credentials \
  --from-literal=POSTGRES_USER=api --from-literal=POSTGRES_PASSWORD="$PW" --from-literal=POSTGRES_DB=api
sudo k3s kubectl -n api create secret generic api-env \
  --from-literal=DATABASE_URL="postgres://api:$PW@postgres.api.svc.cluster.local:5432/api?sslmode=disable"
unset PW
```
A senha não aparece na tela. Para ler depois:
`sudo k3s kubectl -n api get secret postgres-credentials -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d`.
`sslmode=disable` porque o tráfego fica dentro do cluster. **Crie os Secrets antes do push**, ou os pods
ficam em `CreateContainerConfigError` até eles existirem.

### 2. DNS
Registro `A` `api` → IP da VPS na tailnet, proxy desligado.

### 3. Conferir a infra com a imagem de teste
```bash
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl -n api get pods,pvc,certificate
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

### Banco de dados
- Acesso: `sudo k3s kubectl -n api exec -it postgres-0 -- psql -U api -d api`.
- **Sem backup automático**: os dados ficam no disco da VPS. Para algo mais que testes, faça um
  `pg_dump` periódico para fora da máquina.
- Métricas da API: descomente as anotações `prometheus.io/*` no Service em `manifests/api/api.yaml`.

## Logs, traces e métricas da API (OpenTelemetry)

Stack: **Alloy** (coletor) → **Loki** (logs), **Tempo** (traces) e **Prometheus** (métricas), tudo visto no
Grafana (`https://grafana.eduardofontana.dev`). Retenção de 7 dias em Loki e Tempo (volumes de 10 Gi cada,
`local-path`, sem backup). Nada disso foi testado com uma API de verdade.

```
API ──OTLP──► alloy:4318 ──► Tempo (traces) · Prometheus (métricas, via remote_write) · Loki (logs OTLP)
pods da namespace "api" (API + Postgres) ──► Alloy (lê pela API do Kubernetes) ──► Loki
postgres_exporter (sidecar do Postgres) ──► Prometheus (job "postgres")
```

### O que a API precisa fazer
- **Exportar OTLP.** O Deployment já define `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`
  (`http://alloy.monitoring.svc.cluster.local:4318`) e `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`.
  Basta o SDK do OpenTelemetry da linguagem (Go ou Node) ler essas variáveis.
- **Logs em JSON no stdout, com `trace_id`.** O Alloy coleta o stdout dos pods da namespace `api`, então os
  logs da API e do Postgres caem nas mesmas streams (`{namespace="api"}`). No Loki, o campo `trace_id` do
  JSON vira um link para o trace no Tempo. (A API também pode mandar logs por OTLP; escolha um dos dois
  para não duplicar.)
- **Spans de banco.** Use a instrumentação do driver (`otelpgx` em Go, a instrumentação `pg` no Nest): as
  queries aparecem dentro do trace, no Tempo.

### Ligar o log do Postgres ao trace
O Postgres não fala OpenTelemetry. Sozinhos, o log dele e o trace da API só se relacionam por horário e pod.
Para ligar de verdade, a API deve usar **sqlcommenter**: colocar o `traceparent` como comentário no SQL. O
Postgres já loga statements acima de 250 ms (`log_min_duration_statement`) e esperas por lock, e a linha
carrega o comentário. No Loki, o campo derivado `traceparent` abre o trace no Tempo. No Tempo, o botão de
logs do span busca `{namespace="api"} |= "<traceId>"`.

### Métricas do banco
O sidecar `postgres_exporter` (porta 9187) é coletado pelo job `postgres` do Prometheus. O dashboard
*PostgreSQL Exporter Quickstart* (14114) já vem provisionado no Grafana. Ele só mostra dados depois que o
Postgres da API estiver no ar.

### Conferir depois do deploy
```bash
sudo k3s kubectl -n monitoring get pods                     # loki, tempo, alloy Running
sudo k3s kubectl -n monitoring logs deploy/alloy --tail=30  # sem erros de envio
```
No Grafana: **Explore → Loki** com `{namespace="api"}`; **Explore → Tempo**; e **Connections → Data sources**
para ver Loki e Tempo.
