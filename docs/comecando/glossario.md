# Glossário

> **Resumo:** explicação, em linguagem simples, dos termos que aparecem na documentação.
> **Para quem:** quem nunca mexeu com infraestrutura. **Dificuldade:** iniciante.
> **Palavras-chave:** glossário, o que significa, termos, siglas, definição.

| Termo | O que é, em palavras simples |
|---|---|
| **VPS** | Uma máquina virtual alugada (aqui, grátis) na nuvem, que fica ligada o tempo todo. |
| **OCI** | Oracle Cloud Infrastructure, a nuvem da Oracle onde a VPS roda. |
| **Terraform** | Programa que cria a VPS e a rede lendo arquivos de texto, em vez de clicar no painel da Oracle. |
| **VPN / Tailscale** | Uma rede privada entre os seus dispositivos. Só quem está conectado a ela alcança a VPS. |
| **Tailnet** | O nome que o Tailscale dá à sua rede privada. |
| **SSH** | Forma segura de abrir um terminal dentro da VPS. |
| **Contêiner / imagem** | Uma aplicação empacotada com tudo de que precisa. A *imagem* é o pacote; o *contêiner* é ele rodando. |
| **Kubernetes / k3s** | O sistema que roda e vigia os contêineres. `k3s` é a versão leve usada aqui. |
| **Pod** | A menor unidade que o Kubernetes roda: um ou mais contêineres juntos. |
| **Namespace** | Uma "pasta" dentro do cluster que separa os recursos (por exemplo `api`, `postgres`, `monitoring`). |
| **Deployment** | A instrução "mantenha esta aplicação rodando com N cópias". |
| **Service** | O endereço interno fixo de uma aplicação dentro do cluster. |
| **Ingress** | A regra que liga um endereço de internet (`api.eduardofontana.dev`) a um Service. |
| **Traefik** | O programa de entrada que recebe as conexões HTTPS e as entrega ao Ingress certo. |
| **Certificado / cert-manager** | O "cadeado" do HTTPS. O cert-manager pede e renova os certificados (Let's Encrypt) sozinho. |
| **Secret** | Objeto do Kubernetes que guarda senhas e chaves. Fica só no cluster, nunca no Git. |
| **ArgoCD** | Programa que lê este repositório e faz o cluster ficar igual a ele. |
| **GitOps** | Jeito de operar em que o repositório Git descreve o estado desejado, e uma ferramenta o aplica. |
| **Application (ArgoCD)** | Um item do ArgoCD que aponta para uma pasta do repositório e a mantém aplicada. |
| **Sync** | A ação de o ArgoCD aplicar o que está no repositório. Pode ser automática ou por clique. |
| **OutOfSync** | O cluster está diferente do repositório (ainda não foi aplicado). |
| **Hook PreSync** | Tarefa que o ArgoCD roda *antes* de aplicar o resto. Usada para as migrações do banco. |
| **Job** | Tarefa que roda até terminar (diferente de uma aplicação, que roda para sempre). |
| **Kustomize** | Ferramenta que monta os arquivos YAML e troca valores (como a tag da imagem). |
| **Helm / chart** | Pacote pronto de instalação de um programa no Kubernetes. |
| **Postgres** | Banco de dados relacional compartilhado entre as aplicações. |
| **Redis** | Banco de dados em memória, usado para cache e filas. |
| **S3 / SeaweedFS / bucket** | Armazenamento de arquivos. *S3* é o protocolo, *SeaweedFS* é o programa e *bucket* é uma "pasta raiz" de uma aplicação. |
| **Migração** | Um script que altera a estrutura do banco (cria tabela, coluna). A API usa o Prisma para isso. |
| **GHCR** | O repositório de imagens do GitHub (`ghcr.io`), onde o CI guarda a imagem da API. |
| **CI/CD** | Automação que testa (CI) e publica (CD) o código a cada mudança. Aqui usa o GitHub Actions. |
| **PAT / token** | Uma "senha de aplicação" do GitHub, com permissões limitadas. |
| **OpenTelemetry (OTLP)** | Padrão para a aplicação enviar métricas, traces e logs. |
| **Métricas** | Números ao longo do tempo (requisições por segundo, memória). Guardadas no **Prometheus**. |
| **Logs** | O texto que a aplicação escreve. Guardados no **Loki**. |
| **Traces** | O caminho de uma requisição por dentro da aplicação, com tempos. Guardados no **Tempo**. |
| **Grafana** | O painel onde se veem métricas, logs e traces. |
| **Alloy** | O coletor que recebe os dados da aplicação e os entrega ao Prometheus, Loki e Tempo. |
| **DNS (registro A)** | A tabela que diz que `api.eduardofontana.dev` fica em tal IP. É configurada na Cloudflare. |
| **ACL (Redis)** | Lista de permissões de um usuário do Redis (quais chaves e comandos pode usar). |

## Veja também
- [Visão geral](visao-geral.md) · [Índice](../README.md)
