# Solução de problemas

> **Resumo:** tabela de sintomas, causas prováveis e o que fazer, mais os comandos de diagnóstico mais úteis. Comece pelo sintoma.
> **Para quem:** qualquer pessoa, quando algo não funciona. **Dificuldade:** iniciante.
> **Palavras-chave:** erro, problema, não funciona, CreateContainerConfigError, ImagePullBackOff, NOPERM, 403, OutOfSync, certificado, exec format error, diagnóstico, logs.

## Por sintoma
| Sintoma | Causa provável | Onde ver mais |
|---|---|---|
| Pod em `CreateContainerConfigError` / `secret "X" not found` | O Secret `X` ainda não foi criado | [Checklist](../aplicacoes/checklist-nova-aplicacao.md), [Publicar a API](../aplicacoes/publicar-a-api.md) |
| Pod em `ImagePullBackOff` / `unauthorized` | Falta o `ghcr-pull`, token expirado, ou a imagem não existe | [Imagem privada e tokens](../aplicacoes/imagem-privada-e-tokens.md) |
| `exec format error` | Imagem `amd64`; a VPS é `arm64` | [CI/CD](../aplicacoes/ci-cd.md) |
| Application `OutOfSync` | Manual por design (`postgres`, `api`), ou ainda não aplicada | [Como o GitOps funciona](../gitops/como-funciona.md) |
| Sync trava no `PreSync` | A migração do banco falhou | [Migrações](../aplicacoes/migracoes-do-banco.md) |
| Loki/Tempo em `CrashLoopBackOff` no primeiro deploy | O bucket ainda não existe; some sozinho em alguns minutos | [S3](../servicos/armazenamento-s3.md) |
| Endereço `*.eduardofontana.dev` não abre | VPN desligada, registro `A` ausente ou com proxy da Cloudflare ligado | [Domínio e certificados](../rede-e-certificados/dominio-e-certificados.md) |
| Certificado `READY=False` | Token da Cloudflare errado ou sem permissão | [Domínio e certificados](../rede-e-certificados/dominio-e-certificados.md) |
| CI: `Input required and not supplied: token` | `GITOPS_TOKEN` ausente ou fora do alcance do job | [CI/CD](../aplicacoes/ci-cd.md) |
| `OutOfHostCapacity` no Terraform | Sem máquinas ARM livres na zona | [Subir a VPS](../infraestrutura/subir-a-vps.md) |
| Redis `NOPERM No permissions to access a key` | Chave sem o prefixo `<app>:` | [Redis](../servicos/redis.md) |
| Redis `NOPERM ... run the '<comando>' command` | Comando administrativo bloqueado de propósito | [Redis](../servicos/redis.md) |
| Redis `WRONGPASS` / `NOAUTH` | Senha errada ou conexão sem a URL do Secret | [Redis](../servicos/redis.md) |
| Redis: escrita falha com `OOM` | Memória cheia (`noeviction`); apague chaves ou use TTL | [Redis](../servicos/redis.md) |
| Postgres `permission denied for database` | Conectando no banco de outra aplicação | [Postgres](../servicos/postgres.md) |
| Postgres `password authentication failed` | Senha ou usuário errados; releia o Secret | [Postgres](../servicos/postgres.md) |
| S3 `403` / `AccessDenied` | Bucket de outra identidade, ou identidade ainda não criada | [S3](../servicos/armazenamento-s3.md) |
| S3 `UnknownError` (um `HEAD` com 403) só com OpenTelemetry | Cabeçalho assinado e reescrito pela instrumentação `http` | [S3](../servicos/armazenamento-s3.md) |
| S3 `InvalidBucketName`, erro de DNS ou `NoSuchBucket` | Faltou `forcePathStyle`, ou o bucket não foi criado | [S3](../servicos/armazenamento-s3.md) |
| `/v1/health/ready` responde 503 | Dependência fora do ar (banco, Redis ou storage); veja o corpo da resposta | [Publicar a API](../aplicacoes/publicar-a-api.md) |
| Dashboard do Grafana sem dados | A API não está exportando OTLP, ou não houve tráfego | [Logs, traces e métricas](../observabilidade/logs-traces-e-metricas.md) |
| Gravações no S3 travam, "Not enough data nodes" | Disco da VPS acima de 95% (limite `minFreeSpace`) | [S3](../servicos/armazenamento-s3.md) |

## Comandos de diagnóstico
Todos pela VPN. Abra um terminal na VPS com `ssh ubuntu@100.95.76.83` ou prefixe cada comando com `ssh ubuntu@100.95.76.83`.

```bash
sudo k3s kubectl -n argocd get applications          # estado de cada Application (Synced/OutOfSync, Healthy)
sudo k3s kubectl get pods -A                         # todos os pods e se estão Running
sudo k3s kubectl -n <namespace> get pods,secrets     # pods e Secrets de uma namespace
sudo k3s kubectl -n <namespace> describe pod <pod>   # eventos: mostra a causa de CreateContainerConfigError, ImagePullBackOff...
sudo k3s kubectl -n <namespace> logs <pod> --tail=50 # últimas linhas de log
sudo k3s kubectl get certificate -A                  # certificados HTTPS (READY=True)
```
Namespaces: `argocd`, `api`, `postgres`, `redis`, `seaweedfs`, `monitoring`, `cert-manager`, `tailscale`.

> **Cuidado ao colar saídas num chat ou ticket:** nunca cole o conteúdo de Secrets nem a saída de `s3.configure` (imprime chaves). `kubectl get secret` sem `-o yaml` mostra só os nomes.

## Veja também
- [Índice](../README.md) · [Glossário](../comecando/glossario.md) · [Guia para assistentes de IA](para-assistentes-de-ia.md)
