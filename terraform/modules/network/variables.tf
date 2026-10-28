variable "compartment_ocid" {
  type = string
}

variable "name" {
  description = "Prefixo usado nos nomes dos recursos"
  type        = string
}

variable "vcn_cidr" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "ssh_allowed_cidr" {
  type = string
}

variable "enable_public_ssh" {
  type = bool
}

variable "public_tcp_ports" {
  type = list(number)
}
