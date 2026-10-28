module "network" {
  source = "../../modules/network"

  compartment_ocid  = var.compartment_ocid
  name              = var.instance_name
  vcn_cidr          = var.vcn_cidr
  subnet_cidr       = var.subnet_cidr
  ssh_allowed_cidr  = var.ssh_allowed_cidr
  enable_public_ssh = var.enable_public_ssh
  public_tcp_ports  = var.public_tcp_ports
}

module "compute" {
  source = "../../modules/compute"

  tenancy_ocid              = var.tenancy_ocid
  compartment_ocid          = var.compartment_ocid
  subnet_id                 = module.network.subnet_id
  name                      = var.instance_name
  shape                     = var.instance_shape
  ocpus                     = var.instance_ocpus
  memory_gb                 = var.instance_memory_gb
  boot_volume_gb            = var.boot_volume_gb
  availability_domain_index = var.availability_domain_index
  ssh_public_key_path       = var.ssh_public_key_path
  tailscale_auth_key        = var.tailscale_auth_key
  tailscale_hostname        = var.tailscale_hostname
  argocd_version            = var.argocd_version
  argocd_domain             = var.argocd_domain
  acme_email                = var.acme_email
  cloudflare_api_token      = var.cloudflare_api_token
  gitops_repo_url           = var.gitops_repo_url
  gitops_revision           = var.gitops_revision
  gitops_path               = var.gitops_path
}
