# Charts Helm de observabilidade

O PromptLab usa manifests nativos em `k8s/`. Estes charts existem para padronizar OpenTelemetry em aplicacoes Helm de outros times.

- `otel-workload`: library chart que gera e valida annotations OTel de Pod.
- `otel-team`: cria uma CR `Instrumentation` por namespace/time e aponta as aplicacoes ao gateway central.

No PromptLab, `k8s/deploy.sh` instala apenas a release `promptlab-otel-team`; os Deployments das APIs possuem as annotations OTel declaradas diretamente em seus YAMLs. Agent, Gateway e Operator ficam em `otel/` e continuam sendo instalados pelos charts oficiais com `bash ./otel/install.sh`.

Destinos e credenciais sao responsabilidade exclusiva da plataforma: `otel/values-local.yaml` seleciona `newrelic`, `grafana` ou ambos. Os charts de time e aplicacao nunca recebem token, endpoint externo ou exporter.

## Onboarding de outro time

```bash
helm upgrade --install payments-otel-team ./charts/otel-team \
  --namespace payments --create-namespace \
  --values ./charts/otel-team/values/payments.yaml \
  --atomic --wait
```

Crie `values/payments.yaml` a partir de `values.yaml`, preenchendo `releaseName` e `instrumentation.name`. Credenciais e exporters pertencem a plataforma OTel, nao ao time.

O library chart aceita `enabled`, `instrumentationName`, `language`, `serviceName`, `serviceVersion`, `environment`, `criticality` e `time`. Ele gera `tags.time`, que a New Relic exibe como tag de entidade APM `time:<valor>`.
