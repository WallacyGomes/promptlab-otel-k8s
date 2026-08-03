# PromptLab no Kind

## Estrutura

```text
k8s/
  namespace.yaml
  postgres/
  catalog-java/
  insights-python/
  store-node/
  traffic-generator/
```

Cada pasta de entidade possui manifests Kubernetes reais. `kustomization.yaml` agrupa os recursos do servico; PostgreSQL e o gerador usam-no tambem para criar ConfigMaps a partir do SQL e do script locais.

## Comandos

Antes de instalar a plataforma OTel, escolha `newrelic`, `grafana` ou ambos em `otel/values-local.yaml`. Esse arquivo tambem concentra o endpoint e o `instanceId` do Grafana; credenciais sao solicitadas pelo instalador e nunca ficam nos manifests da aplicacao.

```bash
bash ./k8s/create-kind-cluster.sh
bash ./otel/install.sh
bash ./k8s/deploy.sh
```

O deploy aplica `namespace.yaml`, registra a `Instrumentation` do time via Helm e executa `kubectl apply -k` em cada pasta de servico. Portanto, editar `k8s/store-node/deployment.yaml`, por exemplo, altera diretamente o Deployment aplicado ao cluster. O Helm nao instala os servicos do PromptLab.

Para validar apenas um servico sem aplicar:

```bash
kubectl kustomize ./k8s/store-node
kubectl kustomize ./k8s/postgres
```

Para aplicar somente a entidade que voce alterou, sem reconstruir imagens:

```bash
kubectl apply -k ./k8s/store-node
kubectl apply -k ./k8s/postgres
```

Use `bash ./k8s/deploy.sh` quando houver mudanca de codigo/imagem ou quando quiser reconciliar todo o lab. Ele aplica todas as pastas; o Kubernetes mantem inalterados os recursos sem diferencas.

## Acesso e diagnostico

```bash
kubectl port-forward -n promptlab service/store-node 3000:3000
kubectl get pods,services,pvc -n promptlab
kubectl logs -n promptlab deployment/traffic-generator -f
```

## Migracao do Helm

O PromptLab nao usa mais o chart Helm de aplicacao. Se existir a release antiga, remova-a uma vez antes do deploy nativo:

```bash
helm uninstall promptlab -n promptlab
```

O `promptlab-otel-team` continua sendo um chart Helm separado, responsavel somente pela CR `Instrumentation`. Agent, Gateway e Operator pertencem a plataforma OTel e sao atualizados por `bash ./otel/install.sh`.

Para alterar apenas o destino ou uma credencial de telemetria, nao reaplique as APIs: execute `bash ./otel/install.sh`. Ele renova somente Agent e Gateway para carregar as variaveis atualizadas. Consulte [a documentacao OTel](../otel/README.md) para selecao de exporters, rotacao de credenciais e diagnostico de `401`.
