# Acesso pela VPN (Tailscale)

> **Resumo:** como a VPN funciona neste projeto e como expor um serviço dentro dela com o Tailscale operator.
> **Para quem:** quem precisa acessar a VPS ou publicar um serviço só para a própria VPN. **Dificuldade:** intermediária.
> **Palavras-chave:** tailscale, vpn, tailnet, operator, acl, oauth client, operator-oauth, magicdns, expor serviço, ts.net.

## O que você precisa saber
- A VPS só é alcançável por quem está na sua **tailnet** (rede privada do Tailscale). Com a VPN desligada, nenhum endereço do projeto responde.
- O IP da VPS dentro da VPN é `100.95.76.83` (para descobrir: `tailscale ip -4 <nome-do-dispositivo>`).
- O **Tailscale operator** é um programa dentro do cluster que cria dispositivos na tailnet para os serviços que você anotar.

## Pré-requisitos do operator (uma vez)

1. **ACL** (painel do Tailscale → Access controls). Em `tagOwners`, adicione:
   ```json
   "tagOwners": {
     "tag:k8s-operator": [],
     "tag:k8s": ["tag:k8s-operator"]
   }
   ```
2. **OAuth client** (Settings → OAuth clients → Generate): escopos `Devices Core: write` e `Auth Keys: write`, ambos com a tag `tag:k8s-operator`. Guarde o *client id* e o *secret*.
3. **HTTPS** habilitado em DNS (já exigido pelo certificado do ArgoCD).
4. **Secret no cluster** (fora do Git). A namespace precisa existir antes:
   ```bash
   kubectl create namespace tailscale
   kubectl -n tailscale create secret generic operator-oauth \
     --from-literal=client_id=<ID> \
     --from-literal=client_secret=<SECRET>
   ```
   Para versionar a credencial no Git, use Sealed Secrets ou SOPS; nunca em texto puro.

O ArgoCD instala o operator a partir de `gitops/groups/networking/tailscale-operator.yaml`.

**Como saber que deu certo:** `kubectl -n tailscale get pods` mostra o pod `Running`, e o dispositivo `tailscale-operator` aparece no painel do Tailscale.

## Expor um serviço na tailnet

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

> Para os endereços `*.eduardofontana.dev` (API, Grafana, ArgoCD) o projeto usa o **Traefik** com certificado do Let's Encrypt, não o Tailscale operator. Veja [Domínio e certificados](../rede-e-certificados/dominio-e-certificados.md) e [Expor uma aplicação com domínio](../aplicacoes/expor-com-dominio.md).

## Se der errado
| Sintoma | Causa provável |
|---|---|
| Pod do operator não sobe | Falta o Secret `operator-oauth`, ou a ACL/OAuth client estão incompletos. |
| Dispositivo não aparece no Tailscale | Escopos ou tag do OAuth client errados (passo 2). |

## Veja também
- [Subir a VPS](subir-a-vps.md) · [Glossário](../comecando/glossario.md)
