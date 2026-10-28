# A VPS e a rede onde ela roda

variable "instance_name" {
  description = "Nome da VPS"
  type        = string
  default     = "vps-free"
}

variable "instance_shape" {
  description = "Shape Always Free: VM.Standard.A1.Flex (ARM) ou VM.Standard.E2.1.Micro (AMD)"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "OCPUs (só A1.Flex; free tier: até 4 no total)"
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Memória em GB (só A1.Flex; free tier: até 24 no total)"
  type        = number
  default     = 12
}

variable "boot_volume_gb" {
  description = "Tamanho do boot volume (free tier: 200 GB no total)"
  type        = number
  default     = 100
}

variable "availability_domain_index" {
  description = "Índice do availability domain (tente outro se der 'Out of host capacity')"
  type        = number
  default     = 0
}

variable "ssh_public_key_path" {
  description = "Caminho da chave pública SSH"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "ssh_allowed_cidr" {
  description = "CIDR com acesso SSH. Restrinja ao seu IP, ex: 200.1.2.3/32"
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_public_ssh" {
  description = "Mantém a porta 22 aberta ao ssh_allowed_cidr. Desligue após validar o acesso via Tailscale"
  type        = bool
  default     = true
}

variable "public_tcp_ports" {
  description = "Portas TCP públicas adicionais. Vazio: todo o acesso passa pela VPN"
  type        = list(number)
  default     = []
}
