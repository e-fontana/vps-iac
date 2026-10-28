# Subir a VPS (Terraform)

> **Resumo:** como criar do zero a máquina na Oracle Cloud, com a rede, o Tailscale, o k3s e o ArgoCD, usando o Terraform.
> **Para quem:** quem vai montar a infra pela primeira vez. **Dificuldade:** intermediária (comandos no terminal).
> **Palavras-chave:** terraform, oracle, oci, vps, make plan, make apply, tfvars, bootstrap, cloud-init, auth key, ssh público.

## Antes de começar
- Conta na Oracle Cloud com **Pay As You Go** ativo e a **API key** criada (os valores vão em `terraform.tfvars`).
- **Tailscale** instalado e logado na sua máquina.
- No painel do Tailscale: **DNS → MagicDNS** ligado e **Enable HTTPS** ligado.
- Uma **auth key** do Tailscale: *one-off* (uso único), não reutilizável, validade de 1 dia.
- Este repositório publicado no GitHub (a VPS precisa clonar `gitops/apps`). Se ele for privado, cadastre as credenciais no ArgoCD depois do boot.

## Passo a passo

**1. Configurar** (na raiz do repositório):
```bash
cp terraform/envs/prod/terraform.tfvars.example terraform/envs/prod/terraform.tfvars   # se ainda não existir; preencha
export TF_VAR_tailscale_auth_key=tskey-auth-...      # fish: set -x TF_VAR_tailscale_auth_key tskey-auth-...
```
Defina `gitops_repo_url` no `terraform.tfvars` (ou deixe vazio para criar a Application raiz depois).

**2. Planejar e aplicar:**
```bash
make plan      # mostra o que será criado, sem alterar nada: leia antes de aplicar
make apply     # pede confirmação (digite yes)
```
Outros comandos: `make init`, `make validate`, `make fmt` (veja `make help`). O bootstrap leva alguns minutos; o log fica na VPS em `/var/log/bootstrap-node.log`.

**3. Acessar pela VPN:**
- SSH: `ssh ubuntu@argocd` (ou `ssh ubuntu@100.95.76.83`).
- Painel do ArgoCD: `https://argocd.eduardofontana.dev` (depois do ingress; antes disso use o túnel descrito em [Domínio e certificados](../rede-e-certificados/dominio-e-certificados.md)).
- Senha inicial do usuário `admin`:
  ```bash
  ssh ubuntu@argocd "sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  ```

**4. Fechar o SSH público** (só depois de conseguir entrar pela VPN): coloque `enable_public_ssh = false` no `terraform.tfvars` e rode `make apply`. Isso altera só a lista de segurança da rede; a VM não é recriada.

## Como saber que deu certo
- `make apply` termina sem erro e mostra os *outputs*.
- `ssh ubuntu@argocd` entra na VPS pela VPN.
- `sudo k3s kubectl -n argocd get pods` mostra os pods do ArgoCD `Running`.

## Se der errado
| Sintoma | O que fazer |
|---|---|
| `Out of host capacity` no apply | A Oracle está sem máquinas ARM livres nessa zona. Tente outro valor de `availability_domain_index` no tfvars. |
| `make plan` diz `TF_VAR_tailscale_auth_key não definida` | Exporte a variável (passo 1). |
| Não consegue entrar por SSH depois do passo 4 | A VPN está desligada. Ligue o Tailscale e tente de novo. |

## Atenção
- `terraform.tfvars`, `*.tfstate` e `*.pem` estão no `.gitignore`. A auth key do Tailscale fica no *state* e no *metadata* da instância: use sempre uma chave de uso único e curta.
- **Alterar o cloud-init/bootstrap (`user_data`) recria a VM.** O Terraform ignora mudanças em `user_data` de propósito (`lifecycle.ignore_changes`) para evitar recriação acidental.

## Estrutura do código
```
terraform/
├── modules/network/   # VCN, subnet e security list (sem portas públicas além do SSH temporário)
├── modules/compute/   # instância Ubuntu + bootstrap (Tailscale, k3s, ArgoCD)
└── envs/prod/         # onde se roda o terraform (tfvars, providers, chamada dos módulos)
```

## Veja também
- [Acesso pela VPN](acesso-pela-vpn.md) · [Domínio e certificados](../rede-e-certificados/dominio-e-certificados.md) · [Visão geral](../comecando/visao-geral.md)
