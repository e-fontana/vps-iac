# Documentação

> **Resumo:** ponto de partida da documentação do projeto. Diz o que existe, para quem é cada documento e qual abrir para cada tarefa.
> **Para quem:** todos, inclusive quem não tem familiaridade técnica. **Palavras-chave:** índice, documentação, mapa, por onde começar, ajuda.

## Por onde começar
- **Nunca vi este projeto:** [Visão geral](comecando/visao-geral.md), depois o [Glossário](comecando/glossario.md).
- **Algo deu errado:** [Solução de problemas](suporte/solucao-de-problemas.md) (comece pelo sintoma).
- **Vou publicar uma aplicação:** [Checklist de uma aplicação nova](aplicacoes/checklist-nova-aplicacao.md).
- **Sou um assistente de IA:** [Guia para assistentes de IA](suporte/para-assistentes-de-ia.md).

## Qual documento abrir para cada tarefa
| Quero... | Documento |
|---|---|
| Entender o que é o projeto e quais são os endereços | [Visão geral](comecando/visao-geral.md) |
| Entender uma palavra que não conheço | [Glossário](comecando/glossario.md) |
| Criar a máquina na Oracle do zero | [Subir a VPS](infraestrutura/subir-a-vps.md) |
| Acessar a VPS ou expor algo na VPN (Tailscale) | [Acesso pela VPN](infraestrutura/acesso-pela-vpn.md) |
| Configurar HTTPS, domínios e a porta de entrada | [Domínio e certificados](rede-e-certificados/dominio-e-certificados.md) |
| Entender como o ArgoCD organiza o cluster | [Como o GitOps funciona](gitops/como-funciona.md) |
| Usar ou instalar o Postgres | [Postgres](servicos/postgres.md) |
| Usar ou instalar o Redis | [Redis](servicos/redis.md) |
| Guardar arquivos (S3) | [Armazenamento S3](servicos/armazenamento-s3.md) |
| Enviar métricas, logs e traces da aplicação | [Logs, traces e métricas](observabilidade/logs-traces-e-metricas.md) |
| Ler o painel da API no Grafana | [Dashboard da API](observabilidade/dashboard-da-api.md) |
| Publicar uma aplicação nova | [Checklist](aplicacoes/checklist-nova-aplicacao.md) |
| Publicar/atualizar a API | [Publicar a API](aplicacoes/publicar-a-api.md) |
| Configurar testes e deploy automáticos | [CI/CD](aplicacoes/ci-cd.md) |
| Criar tokens (GitHub) e dar acesso à imagem privada | [Imagem privada e tokens](aplicacoes/imagem-privada-e-tokens.md) |
| Alterar a estrutura do banco | [Migrações do banco](aplicacoes/migracoes-do-banco.md) |
| Dar um endereço (domínio) a uma aplicação | [Expor com domínio](aplicacoes/expor-com-dominio.md) |
| Diagnosticar um erro | [Solução de problemas](suporte/solucao-de-problemas.md) |

## Organização das pastas
```
docs/
├── README.md                      este índice
├── comecando/                     visão geral e glossário
├── infraestrutura/                criar a VPS (Terraform) e o acesso pela VPN
├── rede-e-certificados/           domínios, HTTPS e a porta de entrada
├── gitops/                        como o ArgoCD organiza o cluster
├── servicos/                      Postgres, Redis e armazenamento S3
├── observabilidade/               logs, traces, métricas e o dashboard
├── aplicacoes/                    publicar aplicações: checklist, CI/CD, tokens, migrações
└── suporte/                       solução de problemas e guia para assistentes de IA
```

## Convenções da documentação
- **Todo documento** começa com um cabeçalho (*Resumo*, *Para quem*, *Palavras-chave*) e termina com *Veja também*.
- **Passo a passo:** os comandos estão em blocos de código e devem ser executados na ordem, **da raiz do repositório `cloud`**, com a VPN ligada.
- **"Como saber que deu certo"** diz como conferir o resultado; **"Se der errado"** lista sintomas e causas.
- **Segredos nunca aparecem** na documentação nem nos scripts: são criados direto no cluster.
- Quando algo **não foi testado**, o documento diz isso.
- **Idioma:** português. Nomes de arquivos, comandos e termos técnicos ficam como no código.
