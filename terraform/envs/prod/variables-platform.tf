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
