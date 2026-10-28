#!/usr/bin/env bash
# Cria (ou atualiza) o Secret que permite ao cluster baixar imagens PRIVADAS do GHCR: um Secret do tipo
# kubernetes.io/dockerconfigjson na namespace da aplicação. O token nunca vira argumento de processo,
# nunca é impresso e passa por stdin.
#
# Rode na SUA máquina (é ela que pede o token) e aponte o kubectl para a VPS pelo ssh:
#   KUBECTL="ssh ubuntu@100.95.76.83 sudo k3s kubectl" bash templates/api/create-pull-secret.sh <namespace> [nome-do-secret] [usuario-github]
# Exemplo:
#   KUBECTL="ssh ubuntu@100.95.76.83 sudo k3s kubectl" bash templates/api/create-pull-secret.sh api ghcr-pull
#
# O token é um Personal Access Token (CLASSIC) com SÓ o escopo read:packages (o GHCR não aceita tokens
# fine-grained): https://github.com/settings/tokens/new?scopes=read:packages
# Ele é lido do terminal sem eco; se o stdin não for um terminal, é lido da primeira linha dele
# (ex.: `pass show ghcr | bash templates/api/create-pull-secret.sh ...`).
# Rodar de novo ATUALIZA o Secret (é assim que se troca um token expirado).
# O Deployment referencia o Secret por `imagePullSecrets: [{name: ghcr-pull}]` (gitops/manifests/api/api.yaml).
# Variáveis: KUBECTL (padrão: "sudo k3s kubectl", para rodar na própria VPS); REGISTRY (padrão: ghcr.io).
set -euo pipefail

NS=${1:?uso: create-pull-secret.sh <namespace> [nome-do-secret] [usuario-github]}
SECRET=${2:-ghcr-pull}
GH_USER=${3:-}
KUBECTL=${KUBECTL:-"sudo k3s kubectl"}
REGISTRY=${REGISTRY:-ghcr.io}

if [[ -z $GH_USER ]]; then
  read -rp 'Usuário do GitHub dono do token: ' GH_USER </dev/tty
fi
[[ $GH_USER =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || { echo "usuário do GitHub inválido" >&2; exit 1; }

if [[ -t 0 ]]; then
  read -rsp 'Token (classic, escopo read:packages): ' TOKEN </dev/tty
  echo
else
  IFS= read -r TOKEN || true   # stdin vazio: cai na validação abaixo, com mensagem
fi
[[ $TOKEN =~ ^[A-Za-z0-9_]+$ ]] || { echo "token vazio ou com caracteres inesperados (esperado algo como ghp_...)" >&2; exit 1; }

AUTH=$(printf '%s:%s' "$GH_USER" "$TOKEN" | base64 -w0)

$KUBECTL create namespace "$NS" --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null
printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' "$REGISTRY" "$GH_USER" "$TOKEN" "$AUTH" |
  $KUBECTL -n "$NS" create secret generic "$SECRET" --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson=/dev/stdin --dry-run=client -o yaml |
  $KUBECTL apply -f - >/dev/null

echo "Secret '$SECRET' (pull de $REGISTRY) criado ou atualizado na namespace '$NS'"
