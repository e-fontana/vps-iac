variable "tenancy_ocid" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "name" {
  type = string
}

variable "shape" {
  type = string
}

variable "ocpus" {
  type = number
}

variable "memory_gb" {
  type = number
}

variable "boot_volume_gb" {
  type = number
}

variable "availability_domain_index" {
  type = number
}

variable "ssh_public_key_path" {
  type = string
}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

variable "tailscale_hostname" {
  type = string
}

variable "argocd_domain" {
  type = string
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "acme_email" {
  type = string
}

variable "argocd_version" {
  type = string
}

variable "gitops_repo_url" {
  description = "Repo Git com as Applications. Vazio: o ArgoCD sobe sem Application raiz"
  type        = string
}

variable "gitops_revision" {
  type = string
}

variable "gitops_path" {
  type = string
}
