#!/usr/bin/env bash
# Gera as chaves do SeaweedFS (S3 local) e cria os Secrets que o cluster precisa. As chaves são
# aleatórias, nunca são impressas e passam por stdin (não aparecem em argumentos de processo).
#
# Uso (rode ANTES do push que ativa o SeaweedFS):
#   ssh ubuntu@<ip-da-vps> 'bash -s' < templates/seaweedfs/create-secrets.sh
#
# Cria:
#   seaweedfs/seaweedfs-s3-config  s3.json com as identidades (admin, loki, tempo)
#   seaweedfs/seaweedfs-admin      chave do admin, usada pelo Job que cria o bucket
#   monitoring/loki-s3             chave do Loki  (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
#   monitoring/tempo-s3            chave do Tempo (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
# Loki e Tempo só enxergam o bucket observability-local (permissões "Ação:bucket" do SeaweedFS).
# Se seaweedfs-s3-config já existir, aborta sem alterar nada (trocar as chaves exige apagar os 4 Secrets).
# Variáveis: KUBECTL (padrão: "sudo k3s kubectl"); BUCKET (padrão: observability-local).
set -euo pipefail

KUBECTL=${KUBECTL:-"sudo k3s kubectl"}
BUCKET=${BUCKET:-observability-local}

if $KUBECTL -n seaweedfs get secret seaweedfs-s3-config >/dev/null 2>&1; then
  echo "o Secret seaweedfs-s3-config já existe; nada foi alterado" >&2
  exit 1
fi

ak() { openssl rand -hex 8; }
sk() { openssl rand -hex 24; }
ADMIN_AK=$(ak); ADMIN_SK=$(sk)
LOKI_AK=$(ak);  LOKI_SK=$(sk)
TEMPO_AK=$(ak); TEMPO_SK=$(sk)

ns() { $KUBECTL create namespace "$1" --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null; }
ns seaweedfs
ns monitoring

scoped="\"Read:$BUCKET\",\"Write:$BUCKET\",\"List:$BUCKET\",\"Tagging:$BUCKET\""
printf '{"identities":[{"name":"admin","credentials":[{"accessKey":"%s","secretKey":"%s"}],"actions":["Admin","Read","Write","List","Tagging"]},{"name":"loki","credentials":[{"accessKey":"%s","secretKey":"%s"}],"actions":[%s]},{"name":"tempo","credentials":[{"accessKey":"%s","secretKey":"%s"}],"actions":[%s]}]}' \
  "$ADMIN_AK" "$ADMIN_SK" "$LOKI_AK" "$LOKI_SK" "$scoped" "$TEMPO_AK" "$TEMPO_SK" "$scoped" |
  $KUBECTL -n seaweedfs create secret generic seaweedfs-s3-config --from-file=s3.json=/dev/stdin --dry-run=client -o yaml |
  $KUBECTL apply -f - >/dev/null

envsecret() { # namespace nome access-key secret-key
  printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' "$3" "$4" |
    $KUBECTL -n "$1" create secret generic "$2" --from-env-file=/dev/stdin --dry-run=client -o yaml |
    $KUBECTL apply -f - >/dev/null
}
envsecret seaweedfs seaweedfs-admin "$ADMIN_AK" "$ADMIN_SK"
envsecret monitoring loki-s3 "$LOKI_AK" "$LOKI_SK"
envsecret monitoring tempo-s3 "$TEMPO_AK" "$TEMPO_SK"

echo "Secrets criados: seaweedfs/seaweedfs-s3-config, seaweedfs/seaweedfs-admin, monitoring/loki-s3, monitoring/tempo-s3"
