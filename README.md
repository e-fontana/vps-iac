# cloud

VPS no Always Free da Oracle (ARM) rodando k3s mínimo + ArgoCD, acessível só pela VPN (Tailscale).

```
cloud/
├── Makefile               # make plan / apply (roda o terraform em terraform/envs/prod)
├── terraform/
│   ├── modules/
│   │   ├── network/    # VCN, subnet, security list (sem portas públicas além do SSH temporário)
│   │   └── compute/    # instância Ubuntu + bootstrap (Tailscale, k3s, ArgoCD, ArgoCD)
│   └── envs/prod/      # onde se roda o terraform (tfvars, providers, chamada dos módulos)
└── gitops/
    └── apps/           # Applications do ArgoCD (sincronizadas automaticamente)
```

## Ordem de execução

### 1. Pré-requisitos (uma vez)
- Conta OCI com Pay As You Go ativo e a API key criada (valores em `terraform.tfvars`).
- **Tailscale** instalado e logado na sua máquina.
- No admin do Tailscale: **DNS → MagicDNS** ligado e **Enable HTTPS**.
- **Auth key** do Tailscale: one-off, não reutilizável, expiração de 1 dia.
- Este repositório publicado no GitHub (a VM precisa clonar `gitops/apps`). Se for privado, cadastre as credenciais no ArgoCD depois do boot.

### 2. Configurar
```bash
cp terraform/envs/prod/terraform.tfvars.example terraform/envs/prod/terraform.tfvars   # se ainda não existir; preencha
# defina gitops_repo_url (ou deixe vazio para criar a Application raiz depois)
export TF_VAR_tailscale_auth_key=tskey-auth-...      # fish: set -x TF_VAR_tailscale_auth_key tskey-auth-...
```

### 3. Subir a infra (da raiz do projeto)
```bash
make plan      # revise antes de aplicar
make apply     # pede confirmação (yes)
```
Outros comandos: `make init`, `make validate`, `make fmt` (veja `make help`).
O bootstrap leva alguns minutos. Log na VM: `/var/log/bootstrap-node.log`.

### 4. Acessar (pela VPN)
- SSH: `ssh ubuntu@argocd`
- UI: `https://argocd.eduardofontana.dev` (depois do ingress; até lá: `ssh -L 8080:localhost:8080 ...` + `kubectl -n argocd port-forward svc/argocd-server 8080:80`)
- Senha inicial do `admin`:
  `ssh ubuntu@argocd "sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"`

### 4b. Domínio e certificados
Os certificados (Let's Encrypt, DNS-01 na Cloudflare) são emitidos pelo **cert-manager** dentro do
cluster e o **Traefik** atende `argocd.eduardofontana.dev` e `grafana.eduardofontana.dev` na 443,
tudo instalado pelo GitOps. Os secrets (token da Cloudflare, senha do Grafana) e a ordem da
migração estão em `gitops/README.md`. Registros DNS: `A` `argocd` e `A` `grafana` → IP da VPS na
tailnet (`tailscale ip -4 <nome-do-dispositivo>`), com o proxy da Cloudflare desligado.

### 5. Fechar o SSH público
Só depois de entrar pela VPN: `enable_public_ssh = false` no tfvars e `terraform apply`
(altera só a security list, não recria a VM).

### 6. Tailscale operator (expor serviços na tailnet)
Siga `gitops/README.md`: ACL, OAuth client e o Secret `operator-oauth` no cluster.
O ArgoCD instala o operator a partir de `gitops/apps/tailscale-operator.yaml`.

### 7. Ingress, certificados e Grafana
`gitops/apps/` também sobe cert-manager, Traefik, Prometheus e Grafana
(`argocd.eduardofontana.dev` e `grafana.eduardofontana.dev`, sem porta). **A ordem importa**:
siga `gitops/README.md` (secrets e liberação da porta 443) antes do `git push`.

## Atenção
- `terraform.tfvars`, `*.tfstate` e `*.pem` estão no `.gitignore`. A auth key do Tailscale fica
  no state e no metadata da instância: use chave one-off de curta duração.
- Alterar o cloud-init/bootstrap (`user_data`) **recria a VM**.
- Se o apply der `Out of host capacity`, tente outro `availability_domain_index`.
