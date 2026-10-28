# GitOps

Tudo em `gitops/apps/` é sincronizado pelo ArgoCD: a Application `root` (criada pelo
bootstrap da VM) observa essa pasta, definida por `gitops_path` no tfvars.
Cada arquivo ali é uma Application filha. Para adicionar um serviço, crie um YAML
nessa pasta e faça push.

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
