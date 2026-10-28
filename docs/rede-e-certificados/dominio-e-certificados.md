# Domínio e certificados (HTTPS)

> **Resumo:** como os endereços `argocd.`, `grafana.` e `api.eduardofontana.dev` ganham HTTPS válido (cadeado) mesmo ficando só dentro da VPN.
> **Para quem:** quem vai instalar ou mexer na entrada de tráfego da VPS. **Dificuldade:** avançada (a ordem dos passos importa).
> **Palavras-chave:** traefik, cert-manager, letsencrypt, cloudflare, dns-01, certificado, https, 443, argocd insecure, ingress, registro A, cloudflare-api-token.

## Como funciona
- O **cert-manager** pede certificados ao Let's Encrypt provando que você controla o domínio por **DNS-01**: ele cria um registro temporário na Cloudflare (por isso precisa do token da Cloudflare). Assim os certificados valem mesmo sem a máquina estar aberta à internet.
- O **Traefik** é a porta de entrada: recebe as conexões na porta **443** e as entrega ao Ingress certo.
- Os registros DNS (`A`) apontam para o **IP da VPS dentro da VPN** (`100.95.76.83`), com o **proxy da Cloudflare desligado**. Por isso só quem está na VPN consegue abrir os endereços.
- Tudo isso é instalado pelo GitOps: `gitops/groups/networking/` e `gitops/groups/observability/`.

## Primeira instalação: a ordem importa

> **Não faça `git push` antes dos passos A e B.** O ArgoCD sincroniza sozinho: o Traefik tentaria ocupar a porta 443, que no começo é do `argocd-server`, e o ClusterIssuer e o Grafana subiriam sem os Secrets.

**A. Criar os Secrets** (na VPS; nada vai ao Git):
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
O token da Cloudflare pode ser o mesmo do certbot (permissão *Edit zone DNS*, restrita à zona). Guarde a senha do Grafana num gerenciador de senhas: o Secret `grafana-admin` é a única fonte dela.

**B. Tirar o ArgoCD da porta 443** (o TLS passa a ser do Traefik):
```bash
sudo k3s kubectl -n argocd patch cm argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}'
sudo k3s kubectl -n argocd patch svc argocd-server --type json -p '[
  {"op":"replace","path":"/spec/type","value":"ClusterIP"},
  {"op":"remove","path":"/spec/ports/0/nodePort"},
  {"op":"remove","path":"/spec/ports/1/nodePort"}]'
sudo k3s kubectl -n argocd rollout restart deploy/argocd-server
sudo systemctl disable --now argocd-cert-renew.timer
```
A partir daqui a tela do ArgoCD fica fora do ar até o Traefik e o certificado subirem (alguns minutos). Se precisar dela antes, abra um túnel:
`ssh -L 8080:localhost:8080 ubuntu@100.95.76.83` e, na VPS, `sudo k3s kubectl -n argocd port-forward svc/argocd-server 8080:80`.

**C. DNS** (Cloudflare): registro `A` `grafana` → `100.95.76.83`, proxy desligado (o `argocd` já existe).

**D. `git push`.** A Application `root` aplica as novas Applications em ondas. Acompanhe:
```bash
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl get certificate -A      # READY=True em ~1-2 min por certificado
sudo k3s kubectl get pods -A
```

## Como saber que deu certo
- `https://argocd.eduardofontana.dev` e `https://grafana.eduardofontana.dev` abrem com cadeado, sem porta no endereço, com a VPN ligada.
- `kubectl get certificate -A` mostra `READY=True`.

## Depois da instalação
- **Grafana:** usuário `admin` e a senha do passo A. Veja [Grafana e dashboards](../observabilidade/dashboard-da-api.md).
- **CLI do ArgoCD** atrás do Traefik: `argocd login argocd.eduardofontana.dev --grpc-web`.
- Opcional: `sudo k3s kubectl -n argocd delete secret argocd-server-tls` (sobra do certbot).

## Notas
- O download dos dashboards do grafana.com roda quando o pod do Grafana inicia e precisa de acesso à internet.
- O Prometheus guarda 15 dias de dados num disco de 10 Gi (`local-path` do k3s). **Não há backup** desses dados.
- O `ingressEndpoint.ip` do Traefik (`gitops/groups/networking/traefik.yaml`) é o IP da VPS na tailnet. Se ele mudar, atualize ali; é só cosmético (status dos Ingress).

## Se der errado
| Sintoma | Causa provável |
|---|---|
| Certificado fica `READY=False` | Token da Cloudflare errado ou sem permissão na zona (`kubectl -n cert-manager logs deploy/cert-manager`). |
| Navegador não abre o endereço | VPN desligada, ou o registro `A` não existe ou está com o proxy da Cloudflare ligado. |
| Grafana em `CreateContainerConfigError` | Falta o Secret `grafana-admin` (passo A). |

## Veja também
- [Expor uma aplicação com domínio](../aplicacoes/expor-com-dominio.md) · [Como o GitOps funciona](../gitops/como-funciona.md)
