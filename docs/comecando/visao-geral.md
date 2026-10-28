# Visão geral

> **Resumo:** este projeto é um pequeno "data center pessoal" gratuito: uma máquina na nuvem da Oracle que roda as suas aplicações, bancos de dados e painéis de monitoramento, e que só pode ser acessada por uma rede privada (VPN).
> **Para quem:** qualquer pessoa, sem conhecimento técnico prévio. **Dificuldade:** iniciante.
> **Palavras-chave:** visão geral, arquitetura, o que é, como funciona, endereços, mapa.

## O que existe aqui

Uma única máquina virtual (a **VPS**) na Oracle Cloud, no plano gratuito (Always Free, processador ARM). Dentro dela roda o **k3s**, uma versão enxuta do Kubernetes, que é o programa que liga, desliga e vigia as aplicações. Quem diz ao k3s o que rodar é o **ArgoCD**, que lê os arquivos deste repositório no GitHub (isso se chama **GitOps**: o repositório é a fonte da verdade, e quem muda o repositório muda a infra).

O acesso é só pela **VPN Tailscale**. Nada é publicado na internet aberta: sem estar conectado à VPN, os endereços abaixo não respondem.

```
 Você (com a VPN ligada)
        │  https
        ▼
 ┌─────────────────────────── VPS na Oracle (k3s) ───────────────────────────┐
 │  Traefik (porta de entrada, cuida do HTTPS)                                 │
 │    ├─ argocd.eduardofontana.dev   → ArgoCD (painel do GitOps)               │
 │    ├─ grafana.eduardofontana.dev  → Grafana (gráficos e logs)               │
 │    └─ api.eduardofontana.dev      → sua API                                 │
 │                                                                             │
 │  Serviços compartilhados: Postgres · Redis · SeaweedFS (S3)                 │
 │  Monitoramento: Alloy → Prometheus (métricas) · Loki (logs) · Tempo (traces)│
 └─────────────────────────────────────────────────────────────────────────────┘
```

## Endereços e valores importantes

| O quê | Valor |
|---|---|
| Painel do ArgoCD | `https://argocd.eduardofontana.dev` |
| Painel do Grafana | `https://grafana.eduardofontana.dev` |
| API | `https://api.eduardofontana.dev` |
| IP da VPS dentro da VPN (Tailscale) | `100.95.76.83` |
| Entrar na VPS por SSH | `ssh ubuntu@100.95.76.83` (ou `ssh ubuntu@argocd`) |
| Repositório do GitOps | `github.com/e-fontana/vpn-iac` (público) |
| Repositório da API | `github.com/e-fontana/api` (privado) |

## O que cada pasta do repositório faz

| Pasta | Para quê serve | Documentação |
|---|---|---|
| `terraform/` | Cria a máquina e a rede na Oracle | [Subir a VPS](../infraestrutura/subir-a-vps.md) |
| `gitops/` | Descreve tudo que roda dentro da máquina | [Como o GitOps funciona](../gitops/como-funciona.md) |
| `templates/` | Scripts e modelos (criar banco, bucket, Dockerfile, CI) | [Checklist de uma aplicação nova](../aplicacoes/checklist-nova-aplicacao.md) |
| `docs/` | Esta documentação | [Índice](../README.md) |

## Regras que valem em todo o projeto

1. **Segredos nunca vão para o Git.** Senhas e tokens são criados direto no cluster por scripts, e nunca aparecem na tela.
2. **O que está no `main` do repositório é o que o ArgoCD aplica.** Alguns serviços não aplicam sozinhos (precisam de um clique em *Sync*) de propósito, porque dependem de segredos criados antes.
3. **Não há backup automático** de nenhum dado (bancos, arquivos, logs). Tudo fica no disco da VPS.
4. **A máquina é ARM (`arm64`).** Imagens de contêiner construídas para `amd64` não funcionam nela (erro `exec format error`).

## Veja também
- [Glossário](glossario.md) · [Índice da documentação](../README.md) · [Solução de problemas](../suporte/solucao-de-problemas.md)
