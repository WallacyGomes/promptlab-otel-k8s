# OpenTelemetry no Kubernetes

Esta instalacao usa o Collector oficial da comunidade como camada neutra entre o cluster e os destinos:

```text
Agent (metricas por node) ──OTLP/gRPC──┐
Aplicacoes, Events e cluster ──OTLP────┼── Gateway ── New Relic / Grafana Cloud
                                        └── unico ponto de exportacao externo
```

Tres componentes sao instalados no namespace `observability`:

- `otel-agent`: DaemonSet com um pod por node para metricas de host, kubelet e containers.
- `otel-gateway`: Deployment singleton para estado do cluster, Kubernetes Events e OTLP de traces, metricas e logs das aplicacoes.
- `otel-operator`: disponibiliza o webhook que injeta a auto-instrumentacao upstream nos workloads opt-in.

Os componentes sao instalados pelos charts oficiais: `open-telemetry/opentelemetry-collector` na versao `0.165.0` e `open-telemetry/opentelemetry-operator` na versao definida em `otel/values-local.yaml`. Helm e mantido aqui porque tambem gerencia RBAC, CRDs, webhook e certificados do Operator.

O Agent coleta metricas de node, kubelet e containers e as encaminha por OTLP/gRPC interno ao Gateway. O Gateway recebe essa telemetria, OTLP das aplicacoes, Kubernetes Events e metricas de cluster. Somente o Gateway possui exporters e credenciais para os destinos escolhidos.

## Onde editar e como aplicar

| Componente | Arquivo de configuracao | Aplicar |
|---|---|---|
| Agent | `otel/agent/values.yaml` | `bash ./otel/install.sh` |
| Gateway | `otel/gateway/values.yaml` | `bash ./otel/install.sh` |
| Operator | `otel/operator/values.yaml` | `bash ./otel/install.sh` |
| Namespace, versoes e destinos | `otel/values-local.yaml` | `bash ./otel/install.sh` |
| `Instrumentation` do PromptLab | `charts/otel-team/values/promptlab.yaml` | `bash ./k8s/deploy.sh` |

O script executa `helm upgrade --install` para os tres componentes. Alterar somente um arquivo nao obriga recriar os Pods dos outros componentes: o Helm atualiza apenas o que mudou. Nao aplique manualmente manifests nos recursos gerenciados por essas releases.

## Pre-requisitos

- Cluster Kind ativo. Crie o padrao com `bash ./k8s/create-kind-cluster.sh`.
- Contexto Kubernetes `kind-*`; este instalador e exclusivo para Kind local.
- Bash, Helm, `curl`, `base64` e `yq` no `PATH`. Docker Desktop nao e necessario.
- No Windows, use Git Bash ou WSL com acesso ao Docker Engine e ao contexto Kind.
- Acesso do cluster a `ghcr.io` para baixar as imagens de auto-instrumentacao.
- Credencial de cada destino listado em `exporters`.

## Escolher destinos e instalar

Em `otel/values-local.yaml`, selecione um ou ambos os destinos:

```yaml
exporters:
  - newrelic
  - grafana
```

Para enviar somente a um backend, deixe somente `newrelic` ou `grafana` na lista. O instalador remove do Gateway o exporter, a autenticacao e as referencias de pipeline do destino que nao estiver selecionado. O Agent sempre envia somente ao Gateway e nunca recebe credenciais de fornecedores.

Com Grafana selecionado, informe `grafana.otlpEndpoint` e `grafana.instanceId`. Crie o token na mesma Stack do Grafana Cloud, com os escopos `metrics:write`, `logs:write` e `traces:write`.

Depois execute, na raiz do projeto:

```bash
bash ./otel/install.sh
```

O script reutiliza o Secret `otel-exporter-credentials` quando ele ja existe e solicita somente credenciais ausentes para os destinos selecionados. Credenciais de um destino removido da lista permanecem guardadas, mas nao sao injetadas no Gateway. O Agent nao recebe esse Secret. A regiao New Relic, namespace, releases e destinos ficam em `otel/values-local.yaml`. Ele instala somente a plataforma: Agent, Gateway e Operator. A CR `Instrumentation` pertence ao chart `otel-team` de cada time.

Ao final de toda execucao, o script reinicia somente o Agent e o Gateway. Isso e necessario porque as credenciais e endpoints entram nos Pods por variaveis de ambiente; alterar Secret ou ConfigMap nao atualiza um container ja em execucao. As APIs e o Operator nao sao reiniciados.

Para execucao nao interativa, defina temporariamente `NEW_RELIC_LICENSE_KEY` e/ou `GRAFANA_CLOUD_API_TOKEN`. Credenciais nao sao enviadas como argumentos do Helm nem gravadas nos values.

## Rotacionar credenciais

Troque somente o token Grafana Cloud, por exemplo depois de um erro `401`:

```bash
bash ./otel/install.sh --rotate-credentials grafana
```

Para trocar somente a chave New Relic ou todas as credenciais dos destinos selecionados:

```bash
bash ./otel/install.sh --rotate-credentials newrelic
bash ./otel/install.sh --rotate-credentials all
```

Os exporters possuem retry e filas em memoria independentes; uma falha em um destino nao bloqueia o outro. Um `401` do Grafana significa token invalido, de outra Stack ou sem permissao de escrita.

## Endpoint para aplicacoes

```text
http://otel-gateway-opentelemetry-collector.observability.svc.cluster.local:4318
otel-gateway-opentelemetry-collector.observability.svc.cluster.local:4317
```

As aplicacoes usam HTTP `4318` (ou gRPC `4317`). O `otel-agent` usa apenas o segundo, por gRPC, para encaminhar suas metricas de infraestrutura ao Gateway.

O primeiro endpoint e OTLP/HTTP e o segundo e OTLP/gRPC. O Service e `ClusterIP`.

## Auto-instrumentacao das APIs

Cada time instala o chart `otel-team` uma vez no seu namespace. Ele cria uma CR `Instrumentation` namespace-scoped com as imagens dos agentes e o endpoint do gateway. Em aplicacoes Helm, o library chart `otel-workload` pode renderizar as annotations. O `install.sh` nao conhece nem reinicia Deployments de aplicacao.

No PromptLab, instale a plataforma primeiro e depois os manifests nativos da aplicacao:

```bash
bash ./k8s/deploy.sh
```

Em uma instalacao nova, execute primeiro `bash ./otel/install.sh` e depois o comando acima. O `deploy.sh` instala a release `promptlab-otel-team` e aplica os manifests em `k8s/<servico>/`.

Somente os tres Deployments de API recebem um init container `opentelemetry-auto-instrumentation`:

| Deployment | `service.name` |
|---|---|
| `store-node` | `PromptLab Store Api (prd)` |
| `catalog-java` | `PromptLab Catalog Api (prd)` |
| `insights-python` | `PromptLab Insights Api (prd)` |

Cada API exporta traces e metricas de runtime pelo gateway. Seus logs continuam no stdout/stderr para consulta com `kubectl logs`.

Cada API tambem exporta seus logs como OTLP diretamente ao gateway. O Agent esta com `logsCollection.enabled: false`, portanto nao le `stdout`/`stderr` dos containers. Os logs continuam visiveis com `kubectl logs`, mas chegam a New Relic e Grafana Cloud apenas pelo pipeline OTLP do Gateway. Os Kubernetes Events continuam no mesmo pipeline de logs do Gateway.

Os logs proprios das APIs sao JSON de uma linha, com `timestamp`, `severity`, `severity_number`, `message` e `event.name`. Os logs HTTP adicionam `http.request.method`, `url.path`, `http.response.status_code` e `duration_ms`. Probes de `/health` nao geram logs; `2xx/3xx` usam `INFO`, `4xx` usam `WARN` e `5xx` usam `ERROR`. IPs, headers e corpos nao sao registrados.

Essa configuracao usa os bridges ja presentes nas auto-instrumentacoes: Pino no Node, `logging` no Python e JBoss LogManager no Java. Nao foi necessario adicionar sidecar, biblioteca ou transformacao OTTL.

### Aplicar a mudanca de logs

Atualize primeiro a plataforma para desabilitar o `filelog` do Agent e, depois, recrie as APIs para receberem `OTEL_LOGS_EXPORTER=otlp`:

```bash
bash ./otel/install.sh
bash ./k8s/deploy.sh
```

O segundo comando atualiza a `Instrumentation` e reinicia somente os Pods das tres APIs. Em uma troca normal, pode haver uma janela curta sem envio de logs durante o rollout, mas nao havera duplicacao nos destinos.

Os atributos comuns sao `service.namespace=promptlab`, `service.version=local`, `service.criticality=low`, `deployment.environment.name=local` e `tags.time=promptlab`. A New Relic converte `tags.time` na tag de entidade `time:promptlab`. O atributo simples `time` nao e usado porque o `store-node` o usa como timestamp no corpo JSON do log. Os nomes com `(prd)` sao literais, embora o ambiente do lab seja `local`. No PromptLab, essas annotations ficam visiveis diretamente nos Deployments em `k8s/`; o library chart continua disponivel para outros times.

### Compatibilidade dos agentes Java e Node

O gateway recebe OTLP/HTTP na porta `4318`. Por isso o Java Agent `1.26.0` do `catalog-java` declara `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`: sem essa configuracao ele tenta usar gRPC contra uma porta HTTP e registra `OkHttpGrpcExporter`, `FRAME_SIZE_ERROR` e `Broken pipe`.

O `store-node` usa a imagem de auto-instrumentacao `0.78.0` e declara `NODE_PATH=/app/node_modules`, permitindo que o SDK injetado resolva as dependencias da aplicacao, como Express e `pg`. O Operator injeta o restante da configuracao, incluindo `NODE_OPTIONS`, endpoint e identidade do servico.

O Store continua sendo uma aplicacao ESM, mas carrega somente o Pino por `createRequire`. O Operator atual ativa o SDK Node com `NODE_OPTIONS=--require`; esse hook intercepta o Pino CommonJS e adiciona o `OTelPinoStream`, que transforma cada linha em Log Record OTLP. Um import ESM direto do Pino preservaria o stdout JSON, mas deixaria esse bridge sem interceptacao e os logs nao chegariam ao gateway.

## Diagnosticar

```bash
kubectl get pods,services,daemonsets,deployments -n observability
kubectl logs -n observability daemonset/otel-agent-opentelemetry-collector-agent --tail=200
kubectl logs -n observability deployment/otel-gateway-opentelemetry-collector --tail=200
kubectl logs -n observability deployment/otel-operator-opentelemetry-operator --tail=200
kubectl logs -n observability deployment/otel-gateway-opentelemetry-collector --tail=200 | grep -E 'accepted.*log|exported.*log'
kubectl get instrumentation -n promptlab
kubectl get instrumentation promptlab -n promptlab -o yaml
kubectl get pods -n promptlab
kubectl get pod -n promptlab -l app=store-node -o jsonpath='{.items[0].spec.initContainers[*].name}'
kubectl get events -n observability --sort-by=.lastTimestamp
```

Procure por respostas OTLP `401`, `403`, `429` e `5xx`, filas cheias ou falhas de DNS.

O cluster Kind local usa certificados de kubelet sem IP SAN. Por isso os values do agent usam `insecure_skip_verify: true` somente nessa conexao interna local. Nao copie essa opcao para um cluster de producao.

## Metricas de sistema

O agent coleta por node as metricas de host padronizadas, incluindo `system.cpu.utilization`, `system.memory.utilization`, `system.filesystem.usage`, `system.filesystem.utilization` e `system.network.errors`.

No Kind, o filesystem raiz e um `overlay` virtual. A configuracao coleta somente o mount raiz `/` para evitar os mounts internos e protegidos do containerd.

## Gerar traces de teste

```bash
kubectl run telemetrygen \
  --namespace observability \
  --restart=Never \
  --image=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.156.0 \
  -- traces \
  --otlp-endpoint=otel-gateway-opentelemetry-collector.observability.svc.cluster.local:4317 \
  --otlp-insecure \
  --traces=5

kubectl wait -n observability --for=jsonpath='{.status.phase}'=Succeeded pod/telemetrygen --timeout=180s
kubectl logs -n observability telemetrygen
kubectl delete pod -n observability telemetrygen
```

## Adicionar outro destino

Adicione a definicao do exporter somente aos values do Gateway e inclua seu nome na selecao gerada pelo instalador. O Agent nao muda: ele continua encaminhando metricas ao Gateway. Receivers e processors nao precisam ser alterados.

## Remover

```bash
helm uninstall otel-agent -n observability
helm uninstall otel-gateway -n observability
helm uninstall otel-operator -n observability
kubectl delete namespace observability
```
