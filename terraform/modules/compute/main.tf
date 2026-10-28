data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Ubuntu 24.04 mais recente compatível com o shape escolhido
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  is_flex = endswith(var.shape, ".Flex")

  root_app = templatefile("${path.module}/root-app.yaml.tftpl", {
    gitops_repo_url = var.gitops_repo_url
    gitops_revision = var.gitops_revision
    gitops_path     = var.gitops_path
  })

  bootstrap_script = templatefile("${path.module}/bootstrap.sh.tftpl", {
    tailscale_hostname = var.tailscale_hostname
    tailscale_auth_key = var.tailscale_auth_key
    argocd_version     = var.argocd_version
    gitops_repo_url    = var.gitops_repo_url
  })
}

resource "oci_core_instance" "vps" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  display_name        = var.name
  shape               = var.shape

  dynamic "shape_config" {
    for_each = local.is_flex ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = var.memory_gb
    }
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gb
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = true
    hostname_label   = var.name
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
      script       = local.bootstrap_script
      renew_script = file("${path.module}/renew-argocd-cert.sh")
      root_app     = local.root_app
    }))
  }

  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }
}
