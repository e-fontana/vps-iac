# VPN, ArgoCD, domínio/TLS e GitOps

variable "tailscale_auth_key" {
  description = "Auth key do Tailscale (one-off, com expiração curta). Passe via TF_VAR_tailscale_auth_key"
  type        = string
  sensitive   = true
}

variable "tailscale_hostname" {
  description = "Nome do dispositivo na tailnet; define a URL: https://<nome>.<tailnet>.ts.net"
  type        = string
  default     = "argocd"
}

variable "argocd_version" {
  description = "Tag do ArgoCD, ex: v2.14.11. Use 'stable' apenas para testes"
  type        = string
  default     = "stable"
}

variable "argocd_domain" {
  description = "Domínio da UI do ArgoCD (ex: argocd.eduardofontana.dev). Usa certbot + DNS-01 na Cloudflare. Vazio: usa o nome .ts.net via tailscale cert"
  type        = string
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Token da Cloudflare (Edit zone DNS, só da zona). Passe via TF_VAR_cloudflare_api_token; nunca no tfvars"
  type        = string
  sensitive   = true
  default     = ""
}

variable "acme_email" {
  description = "E-mail para o registro no Let's Encrypt (opcional; vazio registra sem e-mail)"
  type        = string
  default     = ""
}

variable "gitops_repo_url" {
  description = "URL do repo Git com as Applications do ArgoCD (https). Vazio: sem Application raiz"
  type        = string
  default     = ""
}

variable "gitops_revision" {
  description = "Branch ou tag do repo GitOps"
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Pasta do repo que contém os manifests das Applications (monorepo: gitops/apps)"
  type        = string
  default     = "gitops/apps"
}
