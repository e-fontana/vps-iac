# Dashboard "API (NestJS)" no Grafana

> **Resumo:** um painel pronto no Grafana, na pasta "API", com métricas, traces e logs da API. Este documento explica o que cada parte mostra e como alterar o painel.
> **Para quem:** quem acompanha a saúde da API, ou quer mudar o painel. **Dificuldade:** iniciante (ler) / intermediária (alterar).
> **Palavras-chave:** grafana, dashboard, api nestjs, painel, grafana-dashboards, configmap, provider, traceql, latência, p95, 5xx, event loop.

## Como abrir
1. Ligue a VPN e abra `https://grafana.eduardofontana.dev` (usuário `admin`; a senha é a do Secret `grafana-admin`).
2. **Dashboards → pasta "API" → "API (NestJS)".**

## O que cada seção mostra
| Seção | Fonte | O que olhar |
|---|---|---|
| **Visão geral** | Prometheus | requisições/s, % de erros 5xx (vermelho a partir de 5%), latência p95, pods prontos, memória, reinícios na última hora |
| **HTTP (entrada)** | Prometheus | requisições/s por status e por método; latência p50/p95/p99 |
| **Runtime Node.js** | Prometheus | event loop (perto de 100% = a API está saturada), heap, tempo em GC, CPU e memória contra o limite |
| **Postgres** | Prometheus | consultas/s e latência p95 por operação, conexões do pool |
| **HTTP (saída)** | Prometheus | chamadas ao S3 e a outros destinos |
| **Traces (Tempo)** | Tempo (TraceQL) | requisições/s e p95 **por rota**, erros por span, tabelas de traces lentos (> 500 ms) e com erro (clique no Trace ID) |
| **Logs** | Loki | `{namespace="api", container="api"}` |

**p95** quer dizer: 95% das requisições respondem em até esse tempo.

As métricas da API **não** trazem a rota; para ver latência por rota, use a seção de traces.

## Como funciona por baixo
- O painel é um arquivo JSON versionado: `gitops/manifests/grafana-dashboards/api-nestjs.json`, mais um `kustomization.yaml` que o transforma num ConfigMap (`grafana-dashboards-api`).
- A Application `gitops/groups/observability/grafana-dashboards.yaml` aplica a pasta (onda 1, **antes** do Grafana, que monta o ConfigMap e não sobe sem ele).
- No `grafana.yaml`, um *provider* próprio (`api`, pasta "API") o separa dos dashboards do grafana.com (provider `default`). A chave de `dashboardsConfigMaps` é o nome do provider e o diretório onde o chart monta o ConfigMap.

## Alterar o painel
1. Edite o JSON (ou ajuste no Grafana, exporte o JSON e substitua o arquivo). Edições feitas só na tela do Grafana **não** persistem: o arquivo do repositório vence.
2. Faça push. O ArgoCD aplica e o Grafana relê os arquivos em alguns segundos.

Para um **dashboard novo**, adicione outro arquivo `.json` à pasta e à lista `files` do `kustomization.yaml`.

## O que foi verificado
As 28 consultas do Prometheus foram executadas contra o cluster e todas são válidas e devolvem dados; as consultas de traces foram aceitas pelo Tempo (a de erros não tinha dados porque ainda não houve erro); o `helm template` do Grafana renderiza o provider e o mount. **Não foi conferido o visual** no Grafana.

## Se der errado
| Sintoma | Causa provável |
|---|---|
| Painéis "No data" | A API não está enviando métricas (veja [Logs, traces e métricas](logs-traces-e-metricas.md)), ou ainda não houve tráfego. |
| Pod do Grafana travado em `ContainerCreating` | O ConfigMap `grafana-dashboards-api` não existe: sincronize a Application `grafana-dashboards`. |
| Pasta "API" não aparece | O provider `api` não foi aplicado: confira `grafana.yaml` e se o pod reiniciou. |

## Veja também
- [Logs, traces e métricas](logs-traces-e-metricas.md) · [Domínio e certificados](../rede-e-certificados/dominio-e-certificados.md)
