# Guia para assistentes de IA

> **Resumo:** instruções para um assistente de IA (ou para quem o configura) dar suporte usando esta documentação: onde procurar, regras de segurança, o que é verificado e o que não é.
> **Para quem:** modelos de IA que respondem perguntas sobre este projeto, e pessoas que os configuram. **Dificuldade:** referência.
> **Palavras-chave:** IA, assistente, modelo, suporte, instruções, regras, segurança, como responder, mapa da documentação.

## Como usar esta documentação
1. Comece por [docs/README.md](../README.md): ele mapeia **tarefa → documento**.
2. Cada documento segue a mesma estrutura: cabeçalho (*Resumo*, *Para quem*, *Palavras-chave*), contexto, passo a passo, **Como saber que deu certo**, **Se der errado**, **Veja também**. Procure pelas palavras-chave e pela seção *Se der errado*.
3. Para um erro, use a tabela por sintoma em [Solução de problemas](solucao-de-problemas.md).
4. Termos desconhecidos: [Glossário](../comecando/glossario.md).

## Fatos que valem para todo o projeto
- Tudo é acessado **só pela VPN** (Tailscale). IP da VPS na VPN: `100.95.76.83`. Comandos de cluster: `ssh ubuntu@100.95.76.83 'sudo k3s kubectl ...'`.
- Scripts de `templates/` rodam **da raiz do repositório `cloud`**, enviados por SSH (`ssh ... 'bash -s -- <args>' < templates/<...>.sh`).
- Domínio: `eduardofontana.dev` (Cloudflare); `argocd.`, `grafana.` e `api.` apontam para `100.95.76.83` **com o proxy desligado**.
- A VPS é **ARM (`arm64`)**: imagens precisam ser `linux/arm64`.
- Applications **manuais** (clique em *Sync*): `postgres` e `api`. As demais sincronizam sozinhas.
- Não há backup de nenhum dado.

## Regras de segurança ao dar suporte
- **Nunca peça, mostre ou grave** senhas, tokens, chaves do S3 ou o conteúdo de Secrets. Os scripts foram feitos para nunca imprimi-los; mantenha isso.
- Segredos **não vão para o Git** nem para o chat. Oriente a criá-los com os scripts de `templates/` ou com `read -rsp` (sem eco).
- `s3.configure` do `weed shell` imprime as chaves de todas as identidades: não o execute onde a saída é registrada.
- Ações com efeito no cluster ou no GitHub (criar Secrets, *Sync*, push, apagar bucket) são do usuário: **explique e peça confirmação** antes de executar, e diga o que será criado.
- Apagar um bucket **apaga os objetos**; apagar um Secret pode derrubar pods. Avise antes.

## Como responder
- Cite o documento e a seção de onde veio a informação (links relativos).
- Separe o que está **verificado** do que **não foi testado**. Itens ainda não validados:
  - o visual do dashboard no Grafana (as consultas foram validadas);
  - pull real do GHCR na VPS (o script foi testado só contra um registry local);
  - uso de memória da API em `arm64` em produção;
  - `NetworkPolicy` para o gRPC do SeaweedFS (não incluída).
- Se a resposta depender do estado atual do cluster, **consulte** com comandos de leitura (`get`, `describe`, `logs`) em vez de supor.
- Se uma informação conflita com o código, o **código em `gitops/` e `templates/` vence**; sugira corrigir a documentação.
- Use linguagem simples; ao usar um termo técnico, explique-o ou aponte para o [Glossário](../comecando/glossario.md).

## Mapa rápido de arquivos (fora de `docs/`)
| Caminho | O que é |
|---|---|
| `terraform/` | Cria a VPS e a rede na Oracle |
| `gitops/apps/`, `gitops/groups/` | Applications do ArgoCD (um arquivo por serviço) |
| `gitops/manifests/` | YAML que as Applications aplicam (API, bancos, dashboards) |
| `templates/` | Scripts de criação de banco, usuário Redis, bucket, pull secret; modelos de Dockerfile e CI |
| `Makefile` | `make plan` / `make apply` / `make help` |

## Veja também
- [Índice](../README.md) · [Solução de problemas](solucao-de-problemas.md)
