# GitOps

```
gitops/
├── apps/                     # o root lê só aqui: projetos + uma Application por grupo
│   ├── projects.yaml         # AppProjects (networking, observability)
│   ├── networking.yaml       # → groups/networking
│   └── observability.yaml    # → groups/observability
├── groups/
│   ├── networking/           # cert-manager, cert-manager-config, traefik, argocd-ingress, tailscale-operator
│   └── observability/        # prometheus, grafana
└── manifests/                # YAML simples usados pelas Applications (ClusterIssuer, Ingress)
```

A Application `root` (criada pelo bootstrap da VM) observa `gitops/apps`, definido por `gitops_path`
no tfvars. Cada grupo é uma Application que observa a própria pasta em `groups/`, então na interface
do ArgoCD os serviços aparecem agrupados: abra `networking` ou `observability` para ver os filhos,
ou filtre a lista por **Project** ou pelo label `group`.

**Adicionar um serviço:** crie um YAML em `groups/<grupo>/` com `project: <grupo>` e o label
`group: <grupo>`, e faça push. **Novo grupo:** um `AppProject` em `apps/projects.yaml`, um arquivo
`apps/<grupo>.yaml` copiado de um existente e uma pasta `groups/<grupo>/`.

Ordem de sync (ondas): projetos (-1), grupos `networking` (0) e `observability` (1); dentro de cada
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
