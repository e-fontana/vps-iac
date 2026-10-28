#!/usr/bin/env bash
# Gera a senha do administrador (usuário default) do Redis compartilhado e cria o Secret
# redis/redis-credentials. A senha é aleatória, nunca é impressa e passa por stdin.
#
# Uso (rode ANTES do push que ativa o Redis):
#   ssh ubuntu@<ip-da-vps> 'bash -s' < templates/redis/create-secret.sh
#
# Se o Secret já existir, aborta sem alterar nada. Para trocar a senha: apague o Secret, rode de novo e
# reinicie o pod (o start reescreve o usuário default a partir do Secret; os usuários das apps são mantidos).
# Variáveis: KUBECTL (padrão: "sudo k3s kubectl").
set -euo pipefail

KUBECTL=${KUBECTL:-"sudo k3s kubectl"}

if $KUBECTL -n redis get secret redis-credentials >/dev/null 2>&1; then
  echo "o Secret redis-credentials já existe; nada foi alterado" >&2
  exit 1
fi

$KUBECTL create namespace redis --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null
printf 'REDIS_PASSWORD=%s\n' "$(openssl rand -hex 24)" |
  $KUBECTL -n redis create secret generic redis-credentials --from-env-file=/dev/stdin --dry-run=client -o yaml |
  $KUBECTL apply -f - >/dev/null

echo "Secret criado: redis/redis-credentials"
