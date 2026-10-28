# Expor uma aplicação com domínio e HTTPS

> **Resumo:** como dar a uma aplicação um endereço como `meuapp.eduardofontana.dev`, com certificado automático, acessível só pela VPN.
> **Para quem:** quem publica uma aplicação nova. **Dificuldade:** intermediária.
> **Palavras-chave:** ingress, traefik, cert-manager, domínio, https, host, tls, secretName, registro A, letsencrypt.

## Como fazer
1. **Ingress:** use `gitops/manifests/api/ingress.yaml` como modelo e troque o `host`. Ele usa o Traefik (`ingressClassName: traefik`), a anotação `cert-manager.io/cluster-issuer: letsencrypt` e um bloco `tls` com um `secretName` (o cert-manager cria o Secret do certificado).
2. **DNS:** na Cloudflare, registro `A` `meuapp` → `100.95.76.83` (o IP da VPS na VPN), com o **proxy desligado**.
3. Faça push (e *Sync* se a Application for manual).

O certificado leva de 1 a 2 minutos para ficar pronto. Só funciona com a VPN ligada.

## Como saber que deu certo
```bash
ssh ubuntu@100.95.76.83 'sudo k3s kubectl -n meuapp get ingress,certificate'
```
O certificado fica `READY=True` e `https://meuapp.eduardofontana.dev` abre com cadeado.

## Se der errado
| Sintoma | Causa provável |
|---|---|
| Certificado fica `READY=False` | Veja [Domínio e certificados](../rede-e-certificados/dominio-e-certificados.md) (token da Cloudflare). |
| Endereço não abre | VPN desligada, ou o registro `A` não existe / está com proxy ligado. |

## Veja também
- [Domínio e certificados](../rede-e-certificados/dominio-e-certificados.md) · [Checklist de uma aplicação nova](checklist-nova-aplicacao.md)
