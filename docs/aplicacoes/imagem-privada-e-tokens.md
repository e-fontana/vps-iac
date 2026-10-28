# Imagem privada e tokens

> **Resumo:** quando o repositório da aplicação é privado, a imagem no GHCR também é, e são necessários dois tokens diferentes, em lugares diferentes. Este documento mostra como criar cada um.
> **Para quem:** quem configura o CI e a VPS para a aplicação. **Dificuldade:** intermediária.
> **Palavras-chave:** token, GITOPS_TOKEN, ghcr, ghcr-pull, imagePullSecret, PAT, classic, fine-grained, read:packages, ImagePullBackOff, create-pull-secret.sh, pacote público.

## Os dois tokens
| Token | Para quê | Onde fica | Tipo |
|---|---|---|---|
| `GITOPS_TOKEN` | o CI da aplicação gravar a tag nova da imagem no `vpn-iac` | secret do GitHub Actions do repositório **da aplicação** (de ambiente ou de repositório) | *fine-grained*, só o repositório `vpn-iac`, permissão **Contents: Read and write** |
| token de pull | a VPS baixar a imagem privada | Secret do Kubernetes `ghcr-pull`, na namespace da aplicação | **classic**, só o escopo `read:packages` (o GHCR não aceita *fine-grained*) |

O ArgoCD **não precisa de token nenhum**: o `vpn-iac` é público e ele nunca clona o repositório da aplicação.

## Criar o `GITOPS_TOKEN`
(Os caminhos de menu do GitHub podem mudar.)
1. GitHub → foto do perfil → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**.
2. Em *Repository access*, escolha **Only select repositories** e marque `vpn-iac`. Em *Repository permissions*, **Contents: Read and write**.
3. Defina a validade (quando o token expirar, o CI falha na hora de gravar a tag; anote a data para renovar) e gere. **Copie o token agora:** ele não é mostrado de novo.
4. No repositório da aplicação: **Settings → Secrets and variables → Actions → New repository secret**, nome `GITOPS_TOKEN`. (Alternativa: *Settings → Environments → prod → Add environment secret*.)
5. Se a branch `main` do `vpn-iac` tiver proteção, o `push` do CI será recusado.

## Dar à VPS acesso à imagem privada (`ghcr-pull`)
1. Gere um token **classic** só com `read:packages`: <https://github.com/settings/tokens/new?scopes=read:packages>.
2. Da raiz deste repositório, rode (o script pede o usuário e o token sem eco; o token não vira argumento de processo nem aparece na tela):
   ```bash
   KUBECTL="ssh ubuntu@100.95.76.83 sudo k3s kubectl" bash templates/api/create-pull-secret.sh api ghcr-pull
   ```
   Troque `api` pela namespace da sua aplicação.
3. O [manifest da API](../../gitops/manifests/api/api.yaml) já referencia o Secret (`imagePullSecrets: [{name: ghcr-pull}]`).
4. Para trocar um token expirado, rode o mesmo comando de novo: ele atualiza o Secret.

**Alternativa sem token de pull:** tornar o pacote público (página do pacote no GitHub → *Package settings → Change visibility*). O preço é que as camadas da imagem, com o código compilado da aplicação, ficam públicas.

## Como saber que deu certo
```bash
ssh ubuntu@100.95.76.83 'sudo k3s kubectl -n api get secret ghcr-pull'
```
O Secret existe (tipo `kubernetes.io/dockerconfigjson`) e o pod da API não fica em `ImagePullBackOff`.

## O que foi testado
O script foi testado contra um registry privado local com senha: o `docker pull` com o Secret gerado funcionou, e com token errado ou sem credencial foi recusado. **Não** foi testado contra o GHCR real.

## Se der errado
| Sintoma | Causa provável |
|---|---|
| `ImagePullBackOff` / `unauthorized` | `ghcr-pull` ausente, token expirado ou sem `read:packages`. |
| O script diz "token vazio ou com caracteres inesperados" | Cole só o token (algo como `ghp_...`), sem espaços. |
| CI falha ao gravar a tag | `GITOPS_TOKEN` expirado ou sem *Contents: Read and write* no `vpn-iac`. |

## Veja também
- [CI/CD](ci-cd.md) · [Publicar a API](publicar-a-api.md)
