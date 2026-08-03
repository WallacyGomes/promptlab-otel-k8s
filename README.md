# PromptLab: Kubernetes + OpenTelemetry

Lab local com tres APIs, PostgreSQL, gerador de trafego e observabilidade OpenTelemetry.

- O PromptLab usa manifests Kubernetes nativos, organizados por entidade em `k8s/`.
- O OTel usa os charts oficiais via Helm. Assim, Helm cuida de recursos complexos do Collector e Operator, como RBAC, CRDs, webhook e certificados.
- O chart `otel-team` cria somente a `Instrumentation` do namespace `promptlab`.

## Requisitos

- Docker Engine, `kind`, `kubectl`, `helm`, `bash`, `openssl` e `yq`.
- Credencial New Relic e/ou token Grafana Cloud, conforme os destinos escolhidos em `otel/values-local.yaml`.

No Windows, execute no Git Bash ou WSL com acesso ao Docker Engine.

## Seguranca

O repositorio nao armazena tokens do Grafana Cloud ou New Relic, chaves privadas, kubeconfigs nem Secrets Kubernetes com dados reais. O instalador solicita essas credenciais durante a execucao e cria os Secrets diretamente no cluster; nenhum arquivo de credencial e gerado no projeto.

As credenciais padrao do PostgreSQL presentes no codigo existem somente para facilitar a execucao local deste lab. Elas sao conhecidas e nao devem ser reutilizadas em nenhum ambiente real. No Kubernetes, `k8s/deploy.sh` cria uma senha aleatoria no Secret `postgres-credentials` quando ele ainda nao existe.

Os arquivos `k8s/values-local.yaml` e `otel/values-local.yaml` podem permanecer versionados: contem apenas configuracao publica, como o nome do cluster, endpoints e o Instance ID do Grafana. Nunca adicione tokens, senhas ou chaves a eles. Caso uma credencial seja compartilhada acidentalmente, rotacione-a imediatamente.

## Subir o lab

Antes da primeira instalacao, escolha os destinos de telemetria em `otel/values-local.yaml`:

```yaml
exporters:
  - newrelic
  - grafana
```

Remova um nome para enviar somente ao outro destino. Para Grafana, informe tambem o endpoint OTLP, o `instanceId` e use um Cloud Access Policy token com permissao de escrita para metricas, logs e traces.

```bash
bash ./k8s/create-kind-cluster.sh
bash ./otel/install.sh
bash ./k8s/deploy.sh
kubectl port-forward -n promptlab service/store-node 3000:3000
```

Abra <http://localhost:3000>.

## Onde editar

| Entidade | Arquivos Kubernetes |
|---|---|
| Namespace | `k8s/namespace.yaml` |
| PostgreSQL | `k8s/postgres/` |
| Catalog API | `k8s/catalog-java/` |
| Insights API | `k8s/insights-python/` |
| Store API | `k8s/store-node/` |
| Gerador de trafego | `k8s/traffic-generator/` |
| OTel Agent | `otel/agent/values.yaml` |
| OTel Gateway | `otel/gateway/values.yaml` |
| OTel Operator | `otel/operator/values.yaml` |
| Versoes, namespace, destinos e endpoints OTel | `otel/values-local.yaml` |
| Instrumentation do time | `charts/otel-team/values/promptlab.yaml` |

Cada pasta de servico possui o Deployment, Service quando aplicavel, e `kustomization.yaml`. PostgreSQL e o gerador tambem guardam seu SQL ou script no mesmo diretorio. Assim, uma mudanca no YAML de um servico e aplicada diretamente por `kubectl apply -k`.

## Como funciona

`k8s/deploy.sh` constroi as tres imagens, carrega-as no Kind, cria o Secret local do banco caso necessario e aplica as pastas nesta ordem: PostgreSQL, Catalog, Insights, Store e gerador. O Kubernetes reconcilia apenas as diferencas dos manifests. O script reinicia as APIs para usar imagens locais reconstruidas com a mesma tag.

As tres APIs declaram diretamente no seu Deployment as annotations OTel, incluindo `service.name` e `resource.opentelemetry.io/tags.time: promptlab`. PostgreSQL e o gerador nao sao instrumentados. Os logs das APIs seguem por OTLP ao `otel-gateway`; o `otel-agent` nao le mais os arquivos de log dos containers. As metricas de infraestrutura coletadas pelo Agent tambem seguem ao Gateway por OTLP/gRPC; somente ele exporta aos destinos externos, evitando duplicacao.

### Logs das APIs

Os logs escritos pelas tres APIs seguem o mesmo JSON em uma unica linha. Logs de `/health` nao sao emitidos para que probes nao escondam trafego util. Respostas `2xx` e `3xx` usam `INFO`, `4xx` usam `WARN` e `5xx` usam `ERROR`.

```json
{"timestamp":"2026-08-03T14:00:00.000Z","severity":"INFO","severity_number":9,"message":"http.server.request.completed","event.name":"http.server.request.completed","http.request.method":"GET","url.path":"/api/prompts","http.response.status_code":200,"duration_ms":7.2}
```

Os campos HTTP descrevem apenas a requisicao: nao incluem IP, headers ou corpos. Erros inesperados tambem podem gerar um evento separado `error.exception`, com `error.type`, `error.message` e `exception.stacktrace` serializado no proprio JSON.

## Depois de editar

| Alteracao | Comando |
|---|---|
| Codigo, imagem ou YAML de qualquer entidade do PromptLab | `bash ./k8s/deploy.sh` |
| Apenas um manifesto do PromptLab, sem reconstruir imagem | `kubectl apply -k ./k8s/<entidade>` |
| Agent, Gateway, Operator, destinos ou credenciais OTel | `bash ./otel/install.sh` |
| CR `Instrumentation` do time | `bash ./k8s/deploy.sh` |

Exemplo para atualizar somente o Store depois de editar seu Deployment:

```bash
kubectl apply -k ./k8s/store-node
```

Nao use `helm upgrade` para os servicos do PromptLab: eles nao sao mais uma release Helm. Em contrapartida, nao edite os recursos instalados pelo OTel diretamente com `kubectl`; altere os values do componente e execute `otel/install.sh`.

Esse comando renova apenas o Agent e o Gateway para carregar credenciais e endpoints atuais. As APIs do PromptLab e o Operator nao sao reiniciados.

Para trocar uma credencial sem pedir as demais:

```bash
bash ./otel/install.sh --rotate-credentials grafana
bash ./otel/install.sh --rotate-credentials newrelic
```

Um erro `401` nos logs do Gateway para o Grafana indica token invalido, de outra Stack ou sem os escopos de escrita necessarios.

## Operacao

```bash
kubectl get pods,services,pvc -n promptlab
kubectl logs -n promptlab deployment/traffic-generator -f
kubectl scale -n promptlab deployment/traffic-generator --replicas=0
kubectl scale -n promptlab deployment/traffic-generator --replicas=1
```

Para remover somente a aplicacao:

```bash
kubectl delete namespace promptlab
helm uninstall promptlab-otel-team -n promptlab
```

Se houver uma release Helm antiga chamada `promptlab`, execute uma vez `helm uninstall promptlab -n promptlab` antes do primeiro deploy nativo. O script detecta essa situacao para evitar duas fontes de verdade.

## Documentacao

- [Kubernetes local](k8s/README.md)
- [OpenTelemetry](otel/README.md)
- [Charts reutilizaveis OTel](charts/README.md)
