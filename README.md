# cloud

VPS no Always Free da Oracle (ARM) rodando k3s mínimo + ArgoCD, acessível só pela VPN (Tailscale). Hospeda a API
(`api.eduardofontana.dev`), o Postgres, o Redis, um S3 local (SeaweedFS) e o monitoramento (Grafana, Prometheus, Loki, Tempo).

## Documentação
Toda a documentação está em **[docs/](docs/README.md)**, organizada por área e escrita para quem não tem familiaridade técnica.

| Quero... | Abra |
|---|---|
| Entender o projeto | [Visão geral](docs/comecando/visao-geral.md) |
| Criar a infra do zero | [Subir a VPS](docs/infraestrutura/subir-a-vps.md) |
| Publicar uma aplicação | [Checklist de uma aplicação nova](docs/aplicacoes/checklist-nova-aplicacao.md) |
| Resolver um erro | [Solução de problemas](docs/suporte/solucao-de-problemas.md) |
| Dar suporte com uma IA | [Guia para assistentes de IA](docs/suporte/para-assistentes-de-ia.md) |

## Pastas
```
cloud/
├── Makefile      # make plan / make apply (roda o terraform em terraform/envs/prod)
├── terraform/    # cria a VPS e a rede na Oracle
├── gitops/       # o que roda dentro do cluster (o ArgoCD lê aqui)
├── templates/    # scripts (banco, Redis, bucket, pull secret) e modelos (Dockerfile, CI)
└── docs/         # documentação
```

## Atenção
- `terraform.tfvars`, `*.tfstate` e `*.pem` estão no `.gitignore`. Segredos nunca vão para o Git.
- Alterar o cloud-init/bootstrap (`user_data`) **recria a VM**.
