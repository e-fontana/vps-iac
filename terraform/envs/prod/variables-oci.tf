# Credenciais e escopo da OCI

variable "tenancy_ocid" {
  description = "OCID da tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID do usuário da API"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint da API key"
  type        = string
}

variable "private_key_path" {
  description = "Caminho da chave privada da API (.pem)"
  type        = string
}

variable "region" {
  description = "Região OCI (a home region é a única com Always Free), ex: sa-saopaulo-1"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment (pode ser o mesmo da tenancy)"
  type        = string
}
