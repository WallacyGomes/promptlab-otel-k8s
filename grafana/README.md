# Dashboard Kubernetes do PromptLab

O arquivo `dashboards/promptlab-kubernetes.json` e um dashboard para o cluster
local `promptlab-local`. Ele usa os UIDs nativos da stack Grafana Cloud:
`grafanacloud-prom` para metricas e `grafanacloud-logs` para logs.

## Importar

1. Abra **Dashboards** no Grafana Cloud e selecione **New > Import**.
2. Envie `dashboards/promptlab-kubernetes.json`.
3. Confirme a importacao. Os UIDs das fontes ja estao no JSON; nao e necessario
   informar URL, usuario ou token.

## Filtros e limites

- **Cluster** inicia em `promptlab-local`.
- **Agent** filtra somente os graficos de host. Ha um `otel-agent` por node,
  entao cada serie representa um node, identificada pelo nome do Pod do Agent.
- **Namespace** filtra os paineis de Pods e workloads.

O lab nao possui HPA, portanto esse card mostra `0`. Os paineis de Events ficam
vazios ate que o Kubernetes produza um evento; isso e esperado e nao indica erro
de LogQL.

Nao inclua tokens no JSON nem neste diretorio. Use a interface Grafana Cloud para
importar o dashboard e rotacione tokens que tenham sido compartilhados fora de
um cofre de segredos.
