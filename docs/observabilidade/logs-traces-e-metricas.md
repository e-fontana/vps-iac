# Logs, traces e métricas (OpenTelemetry)

> **Resumo:** como a aplicação envia métricas, traces e logs, para onde eles vão e como configurar a aplicação para isso.
> **Para quem:** quem desenvolve uma aplicação, ou investiga um problema. **Dificuldade:** intermediária.
> **Palavras-chave:** opentelemetry, otlp, alloy, prometheus, loki, tempo, métricas, traces, logs, trace_id, sqlcommenter, traceparent, OTEL_EXPORTER_OTLP_ENDPOINT, observabilidade.

## O que cada coisa é
| Dado | O que mostra | Onde fica |
|---|---|---|
| **Métricas** | números ao longo do tempo (requisições por segundo, memória, latência) | Prometheus |
| **Logs** | o texto que a aplicação escreve | Loki |
| **Traces** | o caminho de uma requisição por dentro da aplicação, com o tempo de cada etapa | Tempo |

O **Alloy** é o coletor: a aplicação manda tudo para ele (protocolo OTLP) e ele entrega a cada destino. Tudo é visto no **Grafana** (`https://grafana.eduardofontana.dev`).

```
API ──OTLP──► alloy:4318 ──► Tempo (traces) · Prometheus (métricas, via remote_write) · Loki (logs OTLP)
pods das namespaces "api", "postgres", "seaweedfs" e "redis" ──► Alloy (lê o stdout pela API do Kubernetes) ──► Loki
postgres_exporter (ao lado do Postgres) ──► Prometheus (job "postgres")
```

- **Loki e Tempo guardam os dados no SeaweedFS** (S3 local, bucket `observability-local`); o disco de 10 Gi de cada um guarda só o WAL. Retenção de 7 dias em ambos.
- **O Prometheus** guarda 15 dias num disco de 10 Gi (ele não escreve em S3). Não há backup.
- Validado com a API real (NestJS): métricas, traces e logs chegaram ao Prometheus, ao Tempo e ao Loki.

## O que a aplicação precisa fazer
- **Exportar OTLP.** O Deployment já define as variáveis padrão do SDK do OpenTelemetry:

  | Variável | Valor |
  |---|---|
  | `OTEL_SERVICE_NAME` | o nome da app |
  | `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://alloy.monitoring.svc.cluster.local:4318` |
  | `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` |

  Basta o SDK do OpenTelemetry da linguagem (Go ou Node) ler essas variáveis.
- **Logs em JSON no stdout, com `trace_id`.** O Alloy coleta o stdout dos pods, então os logs da API e do Postgres ficam no mesmo Loki (`{namespace=~"api|postgres"}`). No Grafana, o campo `trace_id` vira um link para o trace. (A API também pode mandar logs por OTLP; escolha um dos dois para não duplicar.)
- **Spans de banco.** Use a instrumentação do driver (`otelpgx` em Go, a instrumentação `pg` no Nest): as consultas aparecem dentro do trace.
- **Métricas:** a API as envia por OTLP; o Prometheus **não** faz *scrape* dela (as anotações `prometheus.io/*` em `gitops/manifests/api/api.yaml` ficam comentadas de propósito). No Prometheus elas têm o label `job="api"` (vem do `service.name`).

## Ligar o log do Postgres ao trace
O Postgres não fala OpenTelemetry; sozinhos, o log dele e o trace da API só se relacionam por horário e pod. Para ligar de verdade, a API deve usar **sqlcommenter**: colocar o `traceparent` como comentário no SQL. O Postgres já loga comandos acima de 250 ms e esperas por lock, e a linha carrega o comentário. No Grafana, o campo `traceparent` abre o trace no Tempo, e o botão de logs do span busca `{namespace=~"api|postgres"} |= "<traceId>"`.

## Métricas do banco
O `postgres_exporter` (porta 9187) é coletado pelo job `postgres` do Prometheus. O dashboard *PostgreSQL Exporter Quickstart* (14114) já vem provisionado no Grafana.

## Como saber que deu certo
```bash
sudo k3s kubectl -n monitoring get pods                     # loki, tempo, alloy, prometheus, grafana Running
sudo k3s kubectl -n monitoring logs deploy/alloy --tail=30  # sem erros de envio
```
No Grafana: **Explore → Loki** com `{namespace=~"api|postgres"}`, **Explore → Tempo**, e o dashboard [API (NestJS)](dashboard-da-api.md).

## Se der errado
| Sintoma | Causa provável |
|---|---|
| Nenhuma métrica da API no Prometheus | A API não está com `OTEL_EXPORTER_OTLP_ENDPOINT` (sem ele o SDK não exporta nada), ou o Alloy está com erro de envio. |
| Logs da API não aparecem no Loki | A namespace não está na lista do Alloy (`gitops/groups/observability/alloy.yaml`, bloco `discovery.kubernetes`). |
| O trace não abre a partir do log | O log não tem o campo `trace_id` em JSON. |

## Veja também
- [Dashboard da API](dashboard-da-api.md) · [Armazenamento S3](../servicos/armazenamento-s3.md) · [Solução de problemas](../suporte/solucao-de-problemas.md)
