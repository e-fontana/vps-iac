ENV ?= prod
TF  := terraform -chdir=terraform/envs/$(ENV)

.DEFAULT_GOAL := help
.PHONY: help init validate fmt plan apply check-key

help: ## Lista os comandos
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'
	@echo "  (ambiente: ENV=$(ENV); troque com make plan ENV=outro)"

init: ## Baixa providers e módulos
	$(TF) init

validate: init ## Valida a configuração
	$(TF) validate

fmt: ## Formata todos os .tf e .tfvars
	terraform -chdir=terraform fmt -recursive

check-key:
	@test -n "$$TF_VAR_tailscale_auth_key" || { \
		echo "TF_VAR_tailscale_auth_key não definida."; \
		echo "  bash/zsh: export TF_VAR_tailscale_auth_key=tskey-auth-..."; \
		echo "  fish:     set -x TF_VAR_tailscale_auth_key tskey-auth-..."; \
		exit 1; }

plan: check-key init ## Mostra o que será criado (não altera nada)
	$(TF) plan

apply: check-key init ## Cria a infra (pede confirmação)
	$(TF) apply
