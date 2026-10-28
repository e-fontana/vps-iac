locals {
  is_flex = endswith(var.shape, ".Flex")
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
    user_data           = base64encode(local.user_data)
  }

  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }
}
