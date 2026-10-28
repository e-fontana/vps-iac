#!/bin/bash
# Emite/renova o certificado do Tailscale e entrega ao argocd-server.
# O argocd-server usa automaticamente o Secret "argocd-server-tls" quando ele existe.
set -euo pipefail

kubectl() { k3s kubectl "$@"; }

DIR=/var/lib/argocd-tls
install -d -m 700 "$DIR"

FQDN=$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')
tailscale cert --cert-file "$DIR/tls.crt" --key-file "$DIR/tls.key" "$FQDN"

# Só mexe no cluster (e reinicia o server) quando o certificado mudou
NEW=$(sha256sum "$DIR/tls.crt" | cut -d' ' -f1)
CUR=$(kubectl -n argocd get secret argocd-server-tls \
  -o jsonpath='{.metadata.annotations.cert-sha256}' 2>/dev/null || true)

if [ "$NEW" != "$CUR" ]; then
  kubectl -n argocd create secret tls argocd-server-tls \
    --cert="$DIR/tls.crt" --key="$DIR/tls.key" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n argocd annotate secret argocd-server-tls cert-sha256="$NEW" --overwrite
  kubectl -n argocd rollout restart deploy/argocd-server
  echo "certificado de $FQDN atualizado"
fi
