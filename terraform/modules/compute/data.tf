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
