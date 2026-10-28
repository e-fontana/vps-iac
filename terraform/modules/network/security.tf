resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.name}-public-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH público (desligue quando o acesso via Tailscale estiver validado)
  dynamic "ingress_security_rules" {
    for_each = var.enable_public_ssh ? [1] : []
    content {
      source   = var.ssh_allowed_cidr
      protocol = "6" # TCP

      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  # Portas públicas adicionais (nenhuma por padrão)
  dynamic "ingress_security_rules" {
    for_each = var.public_tcp_ports
    content {
      source   = "0.0.0.0/0"
      protocol = "6"

      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }

  # ICMP type 3 code 4 (Path MTU Discovery)
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1" # ICMP

    icmp_options {
      type = 3
      code = 4
    }
  }
}
