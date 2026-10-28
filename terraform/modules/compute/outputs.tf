output "public_ip" {
  value = oci_core_instance.vps.public_ip
}

output "image_used" {
  value = data.oci_core_images.ubuntu.images[0].display_name
}
