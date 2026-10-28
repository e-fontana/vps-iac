# CI/CD da aplicação (GitHub Actions)

> **Resumo:** os dois workflows da API (testes e publicação), quando cada um roda, o token que o deploy precisa e como exigir os testes antes de aceitar um PR.
> **Para quem:** quem mantém o repositório da aplicação. **Dificuldade:** intermediária.
> **Palavras-chave:** ci, cd, github actions, workflow, ci.yml, deploy.yml, GITOPS_TOKEN, environment prod, release, workflow_dispatch, required checks, ruleset, arm64, qemu.

## Os modelos
Em `templates/api/` deste repositório:
| Arquivo | Copiar para (repositório da aplicação) | Para quê |
|---|---|---|
| `ci.yml` | `.github/workflows/ci.yml` | testes e build de verificação, em **todo push** |
| `github-actions.yml` | `.github/workflows/deploy.yml` | publica as imagens e atualiza o GitOps |
| `Dockerfile.nest` ou `Dockerfile.go` | `Dockerfile` | imagem da aplicação (o modelo Nest tem o alvo `migrate`, só para Prisma) |

Ajuste os nomes das imagens e o caminho `gitops/manifests/<app>` ao nome da sua aplicação. A aplicação deve ouvir em `0.0.0.0:8080` (variável `PORT`).

## `ci.yml`: roda em todo push
- Job `test`: instala as dependências, gera o Prisma e roda `lint`, `test` e `build`.
- Job `docker-build`: constrói as duas imagens em `arm64` **sem publicar** (garante que continuam construindo para a arquitetura da VPS). Leva uns 4 minutos sem cache (o ARM roda emulado), e o cache é compartilhado com o deploy.
- Execuções antigas da mesma branch são canceladas.

**Tornar os testes obrigatórios no PR** (é uma configuração no GitHub, não um arquivo): no repositório da aplicação, *Settings → Rules → Rulesets* (ou *Branches*) da `main` → ative **Require status checks to pass** e marque `test` e `docker-build`. Eles só aparecem na lista depois de terem rodado uma vez.

## `deploy.yml`: build e deploy
| Evento | Job `build` (publica as imagens no GHCR) | Job `deploy` (atualiza o GitOps) |
|---|---|---|
| push na `main` | roda | **não roda** |
| release publicada | roda | roda |
| disparo manual (*Actions → Run workflow*) | roda | roda |

- O `build` publica `ghcr.io/<dono>/api:<sha>` e `ghcr.io/<dono>/api-migrate:<sha>`, ambas `linux/arm64`.
- O `deploy` grava as duas tags no `gitops/manifests/api/kustomization.yaml` do repositório `vpn-iac` (commit "deploy(api): <sha7>"). Depois é só clicar em *Sync* no ArgoCD (veja [Publicar a API](publicar-a-api.md)).

## O `GITOPS_TOKEN`
É o token com que o `deploy` consegue **gravar** no repositório `vpn-iac`. Como criá-lo e onde guardá-lo: [Imagem privada e tokens](imagem-privada-e-tokens.md).

O job `deploy` declara `environment: prod`. Por isso o token pode ficar:
- num **secret de ambiente** (*Settings → Environments → prod*), ou
- num **secret do repositório** (*Settings → Secrets and variables → Actions*).

Se o erro for `Input required and not supplied: token` no passo de checkout, o token não está visível para o job. Causa comum: o secret foi criado no ambiente `prod` mas o job não declara `environment: prod`.

## Como saber que deu certo
- No GitHub, aba **Actions**: o `ci` fica verde a cada push; o `build-and-deploy` fica verde numa release.
- No `vpn-iac` aparece o commit "deploy(api): <sha7>" alterando o `kustomization.yaml`.

## Se der errado
| Sintoma | Causa provável |
|---|---|
| `Input required and not supplied: token` | `GITOPS_TOKEN` ausente ou no lugar errado (veja acima). |
| `push` do deploy recusado | A branch `main` do `vpn-iac` tem proteção, ou o token não tem *Contents: Read and write*. |
| `deploy` falha com 403/404 no checkout | O token não tem acesso ao repositório `vpn-iac`, ou expirou. |
| Build demora muito | Normal sem cache (QEMU/arm64); as execuções seguintes usam o cache. |

## Veja também
- [Publicar a API](publicar-a-api.md) · [Imagem privada e tokens](imagem-privada-e-tokens.md) · [Migrações do banco](migracoes-do-banco.md)
