# Renderiza os templates de templates/ no user_data da instância.
locals {
  root_app = templatefile("${path.module}/templates/manifests/root-app.yaml.tftpl", {
    gitops_repo_url = var.gitops_repo_url
    gitops_revision = var.gitops_revision
    gitops_path     = var.gitops_path
  })

  bootstrap_script = templatefile("${path.module}/templates/scripts/bootstrap-node.sh.tftpl", {
    tailscale_hostname   = var.tailscale_hostname
    tailscale_auth_key   = var.tailscale_auth_key
    argocd_version       = var.argocd_version
    gitops_repo_url      = var.gitops_repo_url
    cloudflare_api_token = var.cloudflare_api_token
  })

  renew_script = templatefile("${path.module}/templates/scripts/renew-argocd-cert.sh.tftpl", {
    domain     = var.argocd_domain
    acme_email = var.acme_email
  })

  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    script       = local.bootstrap_script
    renew_script = local.renew_script
    root_app     = local.root_app
    domain       = var.argocd_domain
  })
}
