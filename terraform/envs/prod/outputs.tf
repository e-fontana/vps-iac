output "public_ip" {
  description = "IP público da VPS"
  value       = module.compute.public_ip
}

output "ssh_command" {
  description = "Comando para conectar"
  value       = "ssh ubuntu@${module.compute.public_ip}"
}

output "image_used" {
  value = module.compute.image_used
}
