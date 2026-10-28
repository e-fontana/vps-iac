#!/usr/bin/env bash
# Cria, no SeaweedFS (S3 local) da infra, um bucket e uma identidade com acesso só a ele, e grava as chaves
# num Secret na namespace da aplicação. As chaves são aleatórias e nunca são impressas.
#
# Uso (na VPS, ou de fora via ssh):
#   ssh ubuntu@<ip-da-vps> 'bash -s -- <bucket> <namespace> [nome-do-secret]' < templates/seaweedfs/new-bucket.sh
# Exemplo (bucket "meuapp", Secret "meuapp-s3" na namespace "meuapp"):
#   ssh ubuntu@100.95.76.83 'bash -s -- meuapp meuapp' < templates/seaweedfs/new-bucket.sh
#
# A identidade tem o mesmo nome do bucket e só lê, grava, lista e etiqueta objetos nele (não cria buckets nem
# enxerga os dos outros). Vale na hora, sem reiniciar o SeaweedFS, e fica gravada no volume dele; as identidades
# estáticas (admin, loki, tempo) não são afetadas. Se o bucket ou a identidade já existir, aborta sem alterar nada
# (rodar o comando de novo para uma identidade existente somaria uma chave nova, por isso ele recusa).
# Secret criado (na namespace da aplicação): AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, S3_ENDPOINT, S3_BUCKET, S3_REGION.
# Se algo falhar no meio, o script desfaz o que ele mesmo criou (a identidade e o bucket, que ainda está vazio).
# Para remover depois, à mão: apagar só a identidade deixa o bucket e os objetos; apagar o bucket APAGA OS OBJETOS.
#   printf 's3.configure -user=<bucket> -delete -apply\n' | sudo k3s kubectl -n seaweedfs exec -i seaweedfs-0 -c seaweedfs -- weed shell -master=localhost:9333 >/dev/null
#   printf 's3.bucket.delete -name <bucket>\n'            | sudo k3s kubectl -n seaweedfs exec -i seaweedfs-0 -c seaweedfs -- weed shell -master=localhost:9333 >/dev/null
# Variáveis: KUBECTL (padrão: "sudo k3s kubectl").
set -euo pipefail

BUCKET=${1:?uso: new-bucket.sh <bucket> <namespace> [nome-do-secret]}
NS=${2:?uso: new-bucket.sh <bucket> <namespace> [nome-do-secret]}
SECRET=${3:-$BUCKET-s3}
KUBECTL=${KUBECTL:-"sudo k3s kubectl"}

[[ $BUCKET =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]] || { echo "nome de bucket inválido (3 a 63 caracteres: minúsculas, números e hífens; não comece nem termine com hífen)" >&2; exit 1; }
case $BUCKET in
  admin|loki|tempo|observability-local) echo "o nome '$BUCKET' é reservado (identidade ou bucket da própria infra)" >&2; exit 1 ;;
esac

# weed shell dentro do pod; os comandos entram por stdin. ATENÇÃO: a saída do s3.configure inclui chaves de acesso,
# então ela só é guardada em variáveis e nunca impressa. Os avisos de log do SeaweedFS (I/W/E + data) são filtrados.
wshell() { $KUBECTL -n seaweedfs exec -i seaweedfs-0 -c seaweedfs -- weed shell -master=localhost:9333 2>&1 | { grep -v -E '^[IWE][0-9]{4} ' || true; }; }

STATE=$(printf 's3.configure\ns3.bucket.list\n' | wshell)
if ! grep -qF '"identities"' <<<"$STATE"; then
  echo "não consegui falar com o SeaweedFS (o pod seaweedfs-0 está no ar?)" >&2
  exit 1
fi
if grep -qF "\"name\": \"$BUCKET\"" <<<"$STATE"; then
  echo "a identidade '$BUCKET' já existe; nada foi alterado" >&2
  exit 1
fi
if grep -qE "^[[:space:]]+$BUCKET[[:space:]]" <<<"$STATE"; then
  echo "o bucket '$BUCKET' já existe; nada foi alterado" >&2
  exit 1
fi
unset STATE

AK=$(openssl rand -hex 8)
SK=$(openssl rand -hex 24)

# Desfaz o que ESTA execução criou: a identidade e o bucket. O bucket ainda está vazio (ninguém tem as chaves) e
# não existia antes (checado acima), então apagá-lo não perde dados.
undo_all() { printf 's3.configure -user=%s -delete -apply\ns3.bucket.delete -name %s\n' "$BUCKET" "$BUCKET" | wshell >/dev/null || true; }

OUT=$(printf 's3.configure -user=%s -actions=Read,Write,List,Tagging -buckets=%s -access_key=%s -secret_key=%s -apply\ns3.bucket.create -name %s -owner %s\n' \
  "$BUCKET" "$BUCKET" "$AK" "$SK" "$BUCKET" "$BUCKET" | wshell)
if ! grep -qF "created bucket $BUCKET" <<<"$OUT"; then
  undo_all
  echo "falha ao criar o bucket; o que foi criado foi desfeito" >&2
  exit 1
fi
unset OUT

CHECK=$(printf 's3.configure\n' | wshell)
if ! grep -qF "\"name\": \"$BUCKET\"" <<<"$CHECK"; then
  undo_all
  echo "a identidade '$BUCKET' não aparece na configuração depois de criada; o que foi criado foi desfeito" >&2
  exit 1
fi
unset CHECK

if ! { $KUBECTL create namespace "$NS" --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null &&
       printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\nS3_ENDPOINT=http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333\nS3_BUCKET=%s\nS3_REGION=us-east-1\n' "$AK" "$SK" "$BUCKET" |
         $KUBECTL -n "$NS" create secret generic "$SECRET" --from-env-file=/dev/stdin --dry-run=client -o yaml |
         $KUBECTL apply -f - >/dev/null; }; then
  undo_all
  echo "falha ao criar o Secret '$SECRET' na namespace '$NS'; a identidade e o bucket foram removidos" >&2
  exit 1
fi

echo "bucket '$BUCKET' criado; Secret '$SECRET' (chaves de acesso) na namespace '$NS'"
