#!/usr/bin/env bash
set -Eeuo pipefail

rotate_credentials_target=""
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd -- "$script_dir/.." && pwd)"
values_file="$script_dir/values-local.yaml"
cluster_values="$root_dir/k8s/values-local.yaml"
operator_values="$script_dir/operator/values.yaml"
agent_values_base="$script_dir/agent/values.yaml"
gateway_values_base="$script_dir/gateway/values.yaml"

usage() {
  cat <<'EOF'
Uso: bash ./otel/install.sh [--rotate-credentials [newrelic|grafana|all]]

Instala a plataforma OpenTelemetry no cluster Kind definido em k8s/values-local.yaml.
As configuracoes nao secretas ficam em otel/values-local.yaml.

Selecione os destinos em otel/values-local.yaml com exporters: [newrelic, grafana].
Credenciais podem ser fornecidas de forma nao interativa em NEW_RELIC_LICENSE_KEY
e GRAFANA_CLOUD_API_TOKEN.
EOF
}

die() {
  printf 'Erro: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Comando '$1' nao encontrado no PATH."
}

resolve_yq() {
  if command -v yq >/dev/null 2>&1; then
    yq_bin="$(command -v yq)"
  elif [[ -x "${HOME:-}/.local/bin/yq" ]]; then
    yq_bin="$HOME/.local/bin/yq"
  else
    die "yq v4 nao encontrado. Instale-o no PATH ou em ~/.local/bin/yq."
  fi
}

yaml_value() {
  local file="$1"
  local query="$2"
  local value
  value="$("$yq_bin" -r "$query" "$file" 2>/dev/null)" \
    || die "Valor obrigatorio '$query' ausente em $file."
  [[ -n "$value" && "$value" != "null" ]] || die "Valor obrigatorio '$query' ausente em $file."
  printf '%s' "$value"
}

has_exporter() {
  local expected="$1"
  local exporter
  for exporter in "${enabled_exporters[@]}"; do
    [[ "$exporter" == "$expected" ]] && return 0
  done
  return 1
}

render_collector_values() {
  local base_file="$1"
  local output_file="$2"
  local expression='.'

  if [[ "$newrelic_enabled" == false ]]; then
    expression+=' | del(.config.exporters."otlphttp/newrelic") | (.config.service.pipelines[] | select(. != null) | .exporters) |= map(select(. != "otlphttp/newrelic"))'
  fi
  if [[ "$grafana_enabled" == false ]]; then
    expression+=' | del(.config.exporters."otlphttp/grafana") | del(.config.extensions."basicauth/grafana") | .config.service.extensions |= map(select(. != "basicauth/grafana")) | (.config.service.pipelines[] | select(. != null) | .exporters) |= map(select(. != "otlphttp/grafana"))'
  fi

  "$yq_bin" eval "$expression" "$base_file" > "$output_file"
}

read_secret() {
  local environment_variable="$1"
  local prompt="$2"
  local value="${!environment_variable:-}"

  if [[ -z "$value" ]]; then
    [[ -t 0 ]] || die "Defina $environment_variable para execucao nao interativa."
    read -r -s -p "$prompt: " value
    printf '\n' >&2
  fi

  [[ -n "$value" ]] || die "A credencial $environment_variable nao pode ser vazia."
  printf '%s' "$value"
}

secret_has_key() {
  local key="$1"
  local value
  value="$(kubectl get secret "$secret_name" -n "$namespace" -o "jsonpath={.data.$key}" 2>/dev/null || true)"
  [[ -n "$value" ]]
}

secret_data_value() {
  kubectl get secret "$secret_name" -n "$namespace" -o "jsonpath={.data.$1}" 2>/dev/null || true
}

base64_value() {
  printf '%s' "$1" | base64 | tr -d '\r\n'
}

test_https_endpoint() {
  local endpoint="$1"
  local name="$2"

  [[ "$endpoint" == https://* ]] || die "O endpoint $name deve usar HTTPS."
  curl --silent --show-error --connect-timeout 10 --max-time 20 --output /dev/null "$endpoint" \
    || die "Nao foi possivel conectar ao destino $name."
}

while (($# > 0)); do
  case "$1" in
    --rotate-credentials)
      rotate_credentials_target="all"
      if (($# > 1)) && [[ "$2" != -* ]]; then
        rotate_credentials_target="$2"
        shift
      fi
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Opcao desconhecida: $1"
      ;;
  esac
done

require_command kubectl
require_command helm
require_command curl
require_command base64
require_command mktemp
resolve_yq

for file in "$values_file" "$cluster_values" "$operator_values" "$agent_values_base" "$gateway_values_base"; do
  [[ -f "$file" ]] || die "Arquivo de configuracao nao encontrado: $file"
done

namespace="$(yaml_value "$values_file" '.installation.namespace')"
chart="$(yaml_value "$values_file" '.installation.collectorChart')"
chart_version="$(yaml_value "$values_file" '.installation.collectorChartVersion')"
agent_release="$(yaml_value "$values_file" '.installation.agentRelease')"
gateway_release="$(yaml_value "$values_file" '.installation.gatewayRelease')"
operator_chart="$(yaml_value "$values_file" '.installation.operatorChart')"
operator_chart_version="$(yaml_value "$values_file" '.installation.operatorChartVersion')"
operator_release="$(yaml_value "$values_file" '.installation.operatorRelease')"
deployment_environment="$(yaml_value "$values_file" '.installation.deploymentEnvironment')"
cluster_name="$(yaml_value "$cluster_values" '.cluster.name')"

mapfile -t enabled_exporters < <("$yq_bin" -r '.exporters // [] | .[]' "$values_file")
((${#enabled_exporters[@]} > 0)) || die "A lista exporters em $values_file nao pode ser vazia."
declare -A seen_exporters=()
for exporter in "${enabled_exporters[@]}"; do
  case "$exporter" in
    newrelic|grafana) ;;
    *) die "Exporter desconhecido em $values_file: $exporter. Use newrelic ou grafana." ;;
  esac
  [[ -z "${seen_exporters[$exporter]:-}" ]] || die "Exporter duplicado em $values_file: $exporter."
  seen_exporters[$exporter]=true
done

newrelic_enabled=false
grafana_enabled=false
has_exporter newrelic && newrelic_enabled=true
has_exporter grafana && grafana_enabled=true

case "$rotate_credentials_target" in
  ""|all|newrelic|grafana) ;;
  *) die "Destino de rotacao invalido: $rotate_credentials_target. Use newrelic, grafana ou all." ;;
esac
if [[ "$rotate_credentials_target" == newrelic && "$newrelic_enabled" == false ]] || [[ "$rotate_credentials_target" == grafana && "$grafana_enabled" == false ]]; then
  die "O destino de rotacao deve estar presente em exporters: $rotate_credentials_target."
fi

new_relic_endpoint=""
grafana_otlp_endpoint=""
grafana_instance_id=""
if [[ "$newrelic_enabled" == true ]]; then
  new_relic_region="$(yaml_value "$values_file" '.newRelic.region')"
  case "$new_relic_region" in
    US) new_relic_endpoint="https://otlp.nr-data.net" ;;
    EU) new_relic_endpoint="https://otlp.eu01.nr-data.net" ;;
    *) die "newRelic.region deve ser US ou EU em $values_file." ;;
  esac
fi
if [[ "$grafana_enabled" == true ]]; then
  grafana_otlp_endpoint="$(yaml_value "$values_file" '.grafana.otlpEndpoint')"
  grafana_instance_id="$(yaml_value "$values_file" '.grafana.instanceId')"
  [[ "$grafana_otlp_endpoint" == */otlp ]] \
    || die "grafana.otlpEndpoint deve terminar em /otlp."
fi

if [[ "$newrelic_enabled" == true && "$grafana_enabled" == true ]]; then
  destinations="New Relic e Grafana Cloud"
elif [[ "$newrelic_enabled" == true ]]; then
  destinations="New Relic"
else
  destinations="Grafana Cloud"
fi

secret_name="$(yaml_value "$gateway_values_base" '.extraEnvsFrom[] | select(has("secretRef")).secretRef.name')"
configmap_name="$(yaml_value "$gateway_values_base" '.extraEnvsFrom[] | select(has("configMapRef")).configMapRef.name')"

temporary_values_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_values_dir"' EXIT
gateway_values="$temporary_values_dir/gateway-values.yaml"
agent_values="$temporary_values_dir/agent-values.yaml"
render_collector_values "$gateway_values_base" "$gateway_values"
render_collector_values "$agent_values_base" "$agent_values"

current_context="$(kubectl config current-context 2>/dev/null || true)"
[[ "$current_context" == "kind-$cluster_name" ]] \
  || die "Este instalador exige o contexto kind-$cluster_name. Contexto atual: ${current_context:-nenhum}."

kubectl get nodes --request-timeout=15s >/dev/null \
  || die "O cluster Kind nao esta acessivel. Execute bash ./k8s/create-kind-cluster.sh."
if [[ "$newrelic_enabled" == true ]]; then
  test_https_endpoint "$new_relic_endpoint" "New Relic"
fi
if [[ "$grafana_enabled" == true ]]; then
  test_https_endpoint "$grafana_otlp_endpoint" "Grafana Cloud"
fi

cluster_uid="$(kubectl get namespace kube-system -o jsonpath='{.metadata.uid}')"
[[ -n "$cluster_uid" ]] || die "Nao foi possivel obter o UID do cluster."

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

secret_exists=false
if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
  secret_exists=true
fi

new_relic_license_key=""
grafana_api_token=""
if [[ "$newrelic_enabled" == true ]] && { [[ "$secret_exists" == false || "$rotate_credentials_target" == all || "$rotate_credentials_target" == newrelic ]] || ! secret_has_key NEW_RELIC_LICENSE_KEY; }; then
  new_relic_license_key="$(read_secret NEW_RELIC_LICENSE_KEY "New Relic license key")"
fi
if [[ "$grafana_enabled" == true ]] && { [[ "$secret_exists" == false || "$rotate_credentials_target" == all || "$rotate_credentials_target" == grafana ]] || ! secret_has_key GRAFANA_CLOUD_API_TOKEN; }; then
  grafana_api_token="$(read_secret GRAFANA_CLOUD_API_TOKEN "Grafana Cloud Access Policy token")"
fi

new_relic_license_key_data="$(secret_data_value NEW_RELIC_LICENSE_KEY)"
grafana_api_token_data="$(secret_data_value GRAFANA_CLOUD_API_TOKEN)"
if [[ -n "$new_relic_license_key" ]]; then
  new_relic_license_key_data="$(base64_value "$new_relic_license_key")"
fi
if [[ -n "$grafana_api_token" ]]; then
  grafana_api_token_data="$(base64_value "$grafana_api_token")"
fi

if [[ -n "$new_relic_license_key_data" || -n "$grafana_api_token_data" ]]; then
  {
    printf '%s\n' 'apiVersion: v1' 'kind: Secret' 'metadata:' "  name: $secret_name" "  namespace: $namespace" 'type: Opaque' 'data:'
    if [[ -n "$new_relic_license_key_data" ]]; then
      printf '  NEW_RELIC_LICENSE_KEY: %s\n' "$new_relic_license_key_data"
    fi
    if [[ -n "$grafana_api_token_data" ]]; then
      printf '  GRAFANA_CLOUD_API_TOKEN: %s\n' "$grafana_api_token_data"
    fi
  } | kubectl apply -f - >/dev/null
fi
unset new_relic_license_key grafana_api_token new_relic_license_key_data grafana_api_token_data

configmap_args=(create configmap "$configmap_name" -n "$namespace"
  "--from-literal=OTEL_CLUSTER_NAME=$cluster_name"
  "--from-literal=OTEL_CLUSTER_UID=$cluster_uid"
  "--from-literal=OTEL_DEPLOYMENT_ENVIRONMENT=$deployment_environment"
  "--from-literal=OTEL_GATEWAY_GRPC_ENDPOINT=${gateway_release}-opentelemetry-collector.${namespace}.svc.cluster.local:4317"
  --dry-run=client -o yaml)
if [[ "$newrelic_enabled" == true ]]; then
  configmap_args+=("--from-literal=NEW_RELIC_OTLP_ENDPOINT=$new_relic_endpoint")
fi
if [[ "$grafana_enabled" == true ]]; then
  configmap_args+=("--from-literal=GRAFANA_CLOUD_OTLP_ENDPOINT=$grafana_otlp_endpoint"
    "--from-literal=GRAFANA_CLOUD_INSTANCE_ID=$grafana_instance_id")
fi
kubectl "${configmap_args[@]}" | kubectl apply -f - >/dev/null

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update >/dev/null
helm repo update open-telemetry >/dev/null

helm template "$gateway_release" "$chart" --version "$chart_version" --namespace "$namespace" --values "$gateway_values" >/dev/null
helm template "$agent_release" "$chart" --version "$chart_version" --namespace "$namespace" --values "$agent_values" >/dev/null
helm template "$operator_release" "$operator_chart" --version "$operator_chart_version" --namespace "$namespace" --values "$operator_values" >/dev/null

helm upgrade --install "$gateway_release" "$chart" --version "$chart_version" --namespace "$namespace" \
  --values "$gateway_values" --atomic --wait --timeout 10m
helm upgrade --install "$agent_release" "$chart" --version "$chart_version" --namespace "$namespace" \
  --values "$agent_values" --atomic --wait --timeout 10m
helm upgrade --install "$operator_release" "$operator_chart" --version "$operator_chart_version" --namespace "$namespace" \
  --values "$operator_values" --atomic --wait --timeout 10m

kubectl rollout restart deployment/otel-gateway-opentelemetry-collector -n "$namespace"
kubectl rollout restart daemonset/otel-agent-opentelemetry-collector-agent -n "$namespace"
kubectl rollout status deployment/otel-gateway-opentelemetry-collector -n "$namespace" --timeout=180s
kubectl rollout status daemonset/otel-agent-opentelemetry-collector-agent -n "$namespace" --timeout=180s
kubectl rollout status deployment/otel-operator-opentelemetry-operator -n "$namespace" --timeout=180s
kubectl wait --for=condition=Established crd/instrumentations.opentelemetry.io --timeout=180s
kubectl get pods,services,daemonsets,deployments -n "$namespace"

printf '\nOpenTelemetry pronto para %s.\n' "$destinations"
printf 'OTLP gRPC: otel-gateway-opentelemetry-collector.%s.svc.cluster.local:4317\n' "$namespace"
printf 'OTLP HTTP: http://otel-gateway-opentelemetry-collector.%s.svc.cluster.local:4318\n' "$namespace"
printf 'Instale o chart otel-team no namespace de cada time antes das aplicacoes instrumentadas.\n'
