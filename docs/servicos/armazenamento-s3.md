# Armazenamento de arquivos (S3 / SeaweedFS)

> **Resumo:** um armazenamento de arquivos compatível com o S3 da Amazon, rodando na própria VPS (SeaweedFS). Cada aplicação recebe um *bucket* e uma chave que só abre esse bucket. O Loki e o Tempo também guardam seus dados aqui.
> **Para quem:** quem instala o S3 (parte 1) e quem desenvolve uma aplicação (parte 3). **Dificuldade:** intermediária.
> **Palavras-chave:** s3, seaweedfs, bucket, new-bucket.sh, create-secrets.sh, AWS_ACCESS_KEY_ID, forcePathStyle, sigv4, traceparent, 403, UnknownError, upload, arquivos.

## O que é e onde fica
- Namespace `seaweedfs`; SeaweedFS 4.51 em um processo só, 1 réplica, disco de 20 Gi (`local-path`).
- Endereço, **só dentro do cluster**: `http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333` (sem TLS, endereçamento por caminho).
- Um Job (PostSync) cria o bucket `observability-local`, usado pelo Loki e pelo Tempo.
- Cada serviço tem uma **identidade própria**, com permissão só no bucket dele. A Application `seaweedfs` é **automática**. Código: `gitops/groups/infra/seaweedfs.yaml` e `gitops/manifests/seaweedfs/`.

## Parte 1: instalar
**Rode o script ANTES do `git push`.** O Loki e o Tempo dependem do SeaweedFS; sem os Secrets, os pods ficam em `CreateContainerConfigError` e logs e traces ficam sem armazenamento.
```bash
ssh ubuntu@100.95.76.83 'bash -s' < templates/seaweedfs/create-secrets.sh
```
O script gera as chaves (aleatórias, nunca impressas) e cria `seaweedfs-s3-config` e `seaweedfs-admin` (namespace `seaweedfs`), `loki-s3` e `tempo-s3` (namespace `monitoring`). Se já existirem, aborta.

**Como saber que deu certo** (depois do push):
```bash
sudo k3s kubectl -n seaweedfs get pods,pvc                      # seaweedfs-0 Running
sudo k3s kubectl -n seaweedfs logs job/seaweedfs-create-bucket  # "bucket observability-local ok" (o Job some ao terminar)
sudo k3s kubectl -n monitoring get pods                         # loki-0 e tempo-0 Running
```
No primeiro deploy é normal ver `CrashLoopBackOff` no Loki e no Tempo por alguns minutos: sem o bucket eles encerram, e o bucket só é criado depois que o SeaweedFS fica saudável. Some sozinho.

## Parte 2: criar um bucket e uma chave para uma aplicação
```bash
# uso: new-bucket.sh <bucket> <namespace> [nome-do-secret]
ssh ubuntu@100.95.76.83 'bash -s -- api api api-s3' < templates/seaweedfs/new-bucket.sh
```
- Cria a identidade (só lê, grava, lista e etiqueta objetos no próprio bucket), o bucket e o Secret `api-s3` na namespace da aplicação. As chaves não são impressas.
- A chave **vale na hora**, sem reiniciar nada; o Loki e o Tempo não são afetados.
- Se o bucket ou a identidade já existir, o script aborta sem alterar nada. Se algo falhar no meio, ele desfaz o que criou.
- Os nomes `admin`, `loki`, `tempo` e `observability-local` são reservados.
- As chaves ficam no Secret da aplicação **e** no volume do SeaweedFS. Para remover depois, veja o cabeçalho do script (apagar o bucket **apaga os objetos**).

## Parte 3: usar na aplicação
O Secret traz `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` (lidas sozinhas pelo SDK da AWS), `S3_ENDPOINT`, `S3_BUCKET` e `S3_REGION` (`us-east-1`). Dois detalhes: **sem TLS** e **path-style** (`/<bucket>/<chave>`, por isso o `forcePathStyle`).

Node (AWS SDK v3):
```js
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
const s3 = new S3Client({
  endpoint: process.env.S3_ENDPOINT,
  region: process.env.S3_REGION,
  forcePathStyle: true,
  // credenciais: AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY do ambiente
});
await s3.send(new PutObjectCommand({ Bucket: process.env.S3_BUCKET, Key: 'pasta/arquivo.txt', Body: 'conteúdo' }));
```
Go (AWS SDK v2):
```go
cfg, _ := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1")) // credenciais: variáveis AWS_*
client := s3.NewFromConfig(cfg, func(o *s3.Options) {
	o.BaseEndpoint = aws.String(os.Getenv("S3_ENDPOINT"))
	o.UsePathStyle = true
})
```

### Armadilha com OpenTelemetry (assinatura SigV4)
Se a aplicação acrescenta um cabeçalho à requisição ao S3 **antes** de assinar (por exemplo o `traceparent`, no passo `build` do SDK) e a instrumentação `http` do OpenTelemetry o **reescreve** ao enviar, a assinatura deixa de bater e o S3 responde **403**. O SDK mostra só `UnknownError` (um `HEAD` não tem corpo). Foi o que travou o `readiness` da API (503 em `storage`). Registre o cabeçalho **depois** da assinatura (`step: 'finalizeRequest'`, `priority: 'low'`): ele continua sendo enviado, só que fora dos `SignedHeaders`. Verificado com a API real contra o SeaweedFS.

## Acessar o S3 do seu computador
Só pela VPN, com um túnel (não há Ingress de propósito):
```bash
ssh -L 8333:localhost:8333 ubuntu@100.95.76.83 'sudo k3s kubectl -n seaweedfs port-forward svc/seaweedfs-s3 8333:8333'
```
As chaves do administrador estão no Secret `seaweedfs-admin`. O `aws` CLI ou o `curl --aws-sigv4` servem de cliente.

## Limites e riscos
- **Um nó, sem replicação e sem backup.** Os dados ficam no disco da VPS.
- **Disco:** volumes de 512 MB, até 40, num PVC de 20 Gi. Os volumes viram somente leitura com menos de 5% **do disco da máquina** livre (`-volume.minFreeSpace=5`); com o disco da VPS quase cheio, as gravações falham.
- **Segurança:** o gRPC do filer (porta 18888, dentro do pod) aceita gerenciar usuários sem autenticação para quem o alcançar. Só o serviço S3 (8333) é publicado, mas qualquer pod do cluster alcança o IP do pod. Uma `NetworkPolicy` resolveria; não está incluída porque não foi testado se o controlador de rede do k3s a aplica sem atrapalhar a comunicação interna do pod.
- O log mostra um erro de STS ("no signing key found"): refere-se a tokens temporários, que não usamos, e não afetou as identidades estáticas.
- **Cuidado:** o comando `s3.configure` do `weed shell` imprime as chaves de **todas** as identidades em texto; não o rode onde a saída é gravada.
- Trocar o armazenamento do Loki/Tempo **não migra** dados antigos dos volumes.

## Se der errado
| Sintoma | Causa provável |
|---|---|
| `403` / `AccessDenied` | Bucket de outra identidade, ou a identidade ainda não foi criada. |
| `UnknownError` (um `HEAD` com 403) só com OpenTelemetry | A armadilha de assinatura descrita acima. |
| `InvalidBucketName`, erro de DNS ou `NoSuchBucket` | Faltou `forcePathStyle`, ou o bucket não foi criado. |
| Script `new-bucket.sh` diz "a identidade ... não aparece na configuração" | Bug já corrigido (o `weed shell` formata o JSON com dois espaços). Atualize o repositório e rode de novo. |

## Veja também
- [Checklist de uma aplicação nova](../aplicacoes/checklist-nova-aplicacao.md) · [Solução de problemas](../suporte/solucao-de-problemas.md)
