#!/usr/bin/env bash
# Cria, no Redis compartilhado da infra, um usuário (ACL) para uma aplicação e grava a URL de conexão
# num Secret na namespace dela. A senha é aleatória e nunca é impressa.
#
# Uso (na VPS, ou de fora via ssh):
#   ssh ubuntu@<ip-da-vps> 'bash -s -- <app> <namespace> [nome-do-secret]' < templates/redis/new-user.sh
# Exemplo (usuário da API, Secret "api-redis" na namespace "api"):
#   ssh ubuntu@100.95.76.83 'bash -s -- api api api-redis' < templates/redis/new-user.sh
#
# O usuário só acessa chaves e canais com o prefixo "<app>:" e não roda comandos administrativos nem
# perigosos (FLUSHALL, CONFIG, KEYS, ...), nem RANDOMKEY e DBSIZE. LIMITAÇÃO: SCAN continua liberado e
# lista os NOMES (não os valores) das chaves de todos os usuários. O usuário é gravado em
# /data/users.acl (ACL SAVE) e sobrevive a reinícios. Se o usuário já existir, aborta sem alterar nada.
# Secret criado (na namespace da aplicação): REDIS_URL, REDIS_USERNAME, REDIS_PASSWORD, REDIS_KEY_PREFIX.
# Variáveis: KUBECTL (padrão: "sudo k3s kubectl").
set -euo pipefail

APP=${1:?uso: new-user.sh <app> <namespace> [nome-do-secret]}
NS=${2:?uso: new-user.sh <app> <namespace> [nome-do-secret]}
SECRET=${3:-$APP-redis}
KUBECTL=${KUBECTL:-"sudo k3s kubectl"}

[[ $APP =~ ^[a-z][a-z0-9_]{0,31}$ && $APP != default ]] || { echo "nome inválido (minúsculas, números e _; comece com letra; não use 'default')" >&2; exit 1; }

# redis-cli dentro do pod, autenticado como admin; os comandos entram por stdin
rcli() { $KUBECTL -n redis exec -i redis-0 -c redis -- sh -c 'exec redis-cli --no-auth-warning -a "$REDIS_PASSWORD"'; }

if printf 'ACL USERS\n' | rcli | grep -qx "$APP"; then
  echo "o usuário '$APP' já existe; nada foi alterado" >&2
  exit 1
fi

PW=$(openssl rand -hex 24)   # só letras e números: entra na URL sem precisar de escape
OUT=$(printf 'ACL SETUSER %s on >%s ~%s:* &%s:* +@all -@admin -@dangerous +info -randomkey -dbsize\nACL SAVE\n' "$APP" "$PW" "$APP" "$APP" | rcli)
if [[ $(printf '%s\n' "$OUT" | grep -cx OK) -ne 2 ]]; then
  echo "falha ao criar o usuário no Redis (esperado OK nos dois comandos)" >&2
  exit 1
fi

$KUBECTL create namespace "$NS" --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null
printf 'REDIS_URL=redis://%s:%s@redis.redis.svc.cluster.local:6379\nREDIS_USERNAME=%s\nREDIS_PASSWORD=%s\nREDIS_KEY_PREFIX=%s:\n' "$APP" "$PW" "$APP" "$PW" "$APP" |
  $KUBECTL -n "$NS" create secret generic "$SECRET" --from-env-file=/dev/stdin --dry-run=client -o yaml |
  $KUBECTL apply -f - >/dev/null

echo "usuário '$APP' criado (chaves '$APP:*'); Secret '$SECRET' na namespace '$NS'"
