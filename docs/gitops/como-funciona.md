# Como o GitOps funciona

> **Resumo:** o ArgoCD lê a pasta `gitops/` deste repositório e deixa o cluster igual a ela. Este documento explica a organização das pastas, a ordem em que as coisas sobem e como adicionar um serviço.
> **Para quem:** quem vai mudar ou adicionar serviços no cluster. **Dificuldade:** intermediária.
> **Palavras-chave:** argocd, gitops, application, appproject, root, sync, onda, sync-wave, groups, manifests, kustomize, adicionar serviço, outofsync.

## A estrutura

```
gitops/
├── apps/                     # o root lê só aqui: projetos + uma Application por grupo
│   ├── projects.yaml         # AppProjects (groups, networking, infra, observability, workloads)
│   ├── networking.yaml       # → groups/networking
│   ├── observability.yaml    # → groups/observability
│   ├── infra.yaml            # → groups/infra
│   └── workloads.yaml        # → groups/workloads
├── groups/
│   ├── networking/           # cert-manager, cert-manager-config, traefik, argocd-ingress, tailscale-operator
│   ├── observability/        # prometheus, loki, tempo, alloy, grafana, grafana-dashboards
│   ├── infra/                # postgres, redis (compartilhados) e seaweedfs (S3 local)
│   └── workloads/            # api (aplicações próprias)
└── manifests/                # YAML simples usados pelas Applications (ClusterIssuer, Ingress, API, bancos, dashboards do Grafana)
```

A Application `root` (criada pelo bootstrap da VM) observa `gitops/apps` (definido por `gitops_path` no tfvars). Cada **grupo** é uma Application que observa a própria pasta em `groups/`. Na tela do ArgoCD os serviços aparecem agrupados: abra `networking` ou `observability` para ver os filhos, ou filtre a lista por **Project**.

## Ordem de sync (ondas)
Projetos (-1) → grupo `networking` (0) → `infra` e `observability` (1) → `workloads` (2). Dentro de cada grupo, cada Application tem a sua onda (anotação `argocd.argoproj.io/sync-wave`).

## Sync automático ou manual
| Application | Sync | Por quê |
|---|---|---|
| `postgres` e `api` | **manual** (clique em *Sync*) | precisam de Secrets criados antes; sem eles o pod fica em `CreateContainerConfigError` |
| todas as outras (networking, observability, `redis`, `seaweedfs`, dashboards) | automático | `redis` e `seaweedfs` também exigem Secrets, mas como sincronizam sozinhas, o script deve rodar **antes do `git push`** |

Uma Application manual aparece como `OutOfSync` até você clicar em *Sync*. Isso é esperado, não é erro.

## Adicionar um serviço
1. Crie um YAML em `gitops/groups/<grupo>/` com `project: <grupo>` e o label `group: <grupo>`.
2. Faça push. O ArgoCD aplica.

**Novo grupo:** um `AppProject` em `apps/projects.yaml`, um arquivo `apps/<grupo>.yaml` (com `project: groups`) copiado de um existente e uma pasta `groups/<grupo>/`.

**Nova aplicação própria:** siga o [Checklist de uma aplicação nova](../aplicacoes/checklist-nova-aplicacao.md).

## Armadilhas conhecidas
- O ArgoCD remove o valor padrão `directory.recurse: false`; por isso as Applications de grupo não o declaram (declarar causaria `OutOfSync` permanente).
- Segredos **nunca** vão para o repositório: são criados por scripts em `templates/`, direto no cluster.

## Como saber que deu certo
```bash
ssh ubuntu@100.95.76.83 'sudo k3s kubectl -n argocd get applications'
```
Todas devem estar `Synced` e `Healthy`, exceto as manuais ainda não aplicadas (`OutOfSync`).

## Veja também
- [Visão geral](../comecando/visao-geral.md) · [Solução de problemas](../suporte/solucao-de-problemas.md)
