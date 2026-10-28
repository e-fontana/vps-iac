#!/usr/bin/env bash
# Cria, no Postgres compartilhado da infra, um banco + um usuário para uma aplicação e grava o
# DATABASE_URL num Secret na namespace da aplicação. A senha é aleatória e nunca é impressa.
#
# Uso (na VPS, ou de fora via ssh):
#   ssh ubuntu@<ip-da-vps> 'bash -s -- <banco> <namespace> [nome-do-secret]' < templates/postgres/new-database.sh
# Exemplo (banco da API, Secret "api-env" na namespace "api"):
#   ssh ubuntu@100.95.76.83 'bash -s -- api api api-env' < templates/postgres/new-database.sh
#
# Variáveis: KUBECTL (padrão: "sudo k3s kubectl").
# O que faz: usuário e banco com o mesmo nome; só esse usuário conecta no banco (CONNECT é revogado
# de PUBLIC). Se o usuário ou o banco já existir, aborta sem alterar nada.
set -euo pipefail

DB=${1:?uso: new-database.sh <banco> <namespace> [nome-do-secret]}
NS=${2:?uso: new-database.sh <banco> <namespace> [nome-do-secret]}
SECRET=${3:-$DB-db}
KUBECTL=${KUBECTL:-"sudo k3s kubectl"}

[[ $DB =~ ^[a-z][a-z0-9_]{0,31}$ ]] || { echo "nome de banco inválido (use minúsculas, números e _; comece com letra)" >&2; exit 1; }

psql_pg() { $KUBECTL -n postgres exec -i postgres-0 -c postgres -- psql -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"; }

EXISTS=$(psql_pg -tA -c "SELECT (SELECT count(*) FROM pg_roles WHERE rolname = '$DB') + (SELECT count(*) FROM pg_database WHERE datname = '$DB')" </dev/null)
if [[ $EXISTS != 0 ]]; then
  echo "o usuário ou o banco '$DB' já existe; nada foi alterado" >&2
  exit 1
fi

PW=$(openssl rand -hex 24)   # só letras e números: entra na URL sem precisar de escape
psql_pg <<SQL
CREATE ROLE "$DB" LOGIN PASSWORD '$PW';
CREATE DATABASE "$DB" OWNER "$DB";
REVOKE ALL ON DATABASE "$DB" FROM PUBLIC;
SQL

$KUBECTL create namespace "$NS" --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null
$KUBECTL -n "$NS" create secret generic "$SECRET" \
  --from-literal=DATABASE_URL="postgres://$DB:$PW@postgres.postgres.svc.cluster.local:5432/$DB?sslmode=disable" \
  --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null

echo "banco '$DB' criado; Secret '$SECRET' (chave DATABASE_URL) na namespace '$NS'"
