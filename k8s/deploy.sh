#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd -- "$script_dir/.." && pwd)"
cluster_values="$script_dir/values-local.yaml"
namespace_manifest="$script_dir/namespace.yaml"
postgres_dir="$script_dir/postgres"
catalog_dir="$script_dir/catalog-java"
insights_dir="$script_dir/insights-python"
store_dir="$script_dir/store-node"
traffic_dir="$script_dir/traffic-generator"
workload_dirs=("$postgres_dir" "$catalog_dir" "$insights_dir" "$store_dir" "$traffic_dir")
team_chart_dir="$root_dir/charts/otel-team"
team_values="$team_chart_dir/values/promptlab.yaml"

usage() {
  cat <<'EOF'
Uso: bash ./k8s/deploy.sh

Constroi imagens locais e aplica os manifests de cada servico em k8s/<servico>/.
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

if (($# > 0)); then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Opcao desconhecida: $1"
      ;;
  esac
fi

require_command docker
require_command kind
require_command kubectl
require_command openssl
require_command helm
resolve_yq

for file in "$cluster_values" "$namespace_manifest" "$team_values" "$postgres_dir/statefulset.yaml" "$catalog_dir/deployment.yaml" "$insights_dir/deployment.yaml" "$store_dir/deployment.yaml"; do
  [[ -f "$file" ]] || die "Arquivo de configuracao nao encontrado: $file"
done
for directory in "${workload_dirs[@]}"; do
  [[ -f "$directory/kustomization.yaml" ]] || die "Kustomization nao encontrado: $directory/kustomization.yaml"
done

cluster_name="$(yaml_value "$cluster_values" '.cluster.name')"
namespace="$(yaml_value "$namespace_manifest" '.metadata.name')"
team_release="$(yaml_value "$team_values" '.releaseName')"
postgres_manifest="$postgres_dir/statefulset.yaml"
postgres_secret="$(yaml_value "$postgres_manifest" '.spec.template.spec.containers[] | select(.name == "postgres").env[] | select(.name == "POSTGRES_PASSWORD").valueFrom.secretKeyRef.name')"
postgres_database="$(yaml_value "$postgres_manifest" '.spec.template.spec.containers[] | select(.name == "postgres").env[] | select(.name == "POSTGRES_DB").value')"
postgres_username="$(yaml_value "$postgres_manifest" '.spec.template.spec.containers[] | select(.name == "postgres").env[] | select(.name == "POSTGRES_USER").value')"
catalog_image="$(yaml_value "$catalog_dir/deployment.yaml" '.spec.template.spec.containers[] | select(.name == "catalog-java").image')"
insights_image="$(yaml_value "$insights_dir/deployment.yaml" '.spec.template.spec.containers[] | select(.name == "insights-python").image')"
store_image="$(yaml_value "$store_dir/deployment.yaml" '.spec.template.spec.containers[] | select(.name == "store-node").image')"

current_context="$(kubectl config current-context 2>/dev/null || true)"
[[ "$current_context" == "kind-$cluster_name" ]] \
  || die "Este instalador exige o contexto kind-$cluster_name. Contexto atual: ${current_context:-nenhum}."

kubectl get nodes --request-timeout=15s >/dev/null \
  || die "O cluster Kind nao esta acessivel. Execute bash ./k8s/create-kind-cluster.sh."
kubectl get crd instrumentations.opentelemetry.io >/dev/null 2>&1 \
  || die "O OpenTelemetry Operator ainda nao esta instalado. Execute bash ./otel/install.sh antes do deploy."

kubectl apply -f "$namespace_manifest" >/dev/null

if helm status promptlab -n "$namespace" >/dev/null 2>&1; then
  die "A release Helm antiga 'promptlab' existe. Execute uma vez: helm uninstall promptlab -n $namespace. O PVC do PostgreSQL sera preservado."
fi

printf 'Construindo imagens locais...\n'
docker build -t "$catalog_image" "$root_dir/services/catalog-java"
docker build -t "$insights_image" "$root_dir/services/insights-python"
docker build -t "$store_image" "$root_dir/services/store-node"

printf 'Carregando imagens no cluster Kind...\n'
kind load docker-image --name "$cluster_name" "$catalog_image" "$insights_image" "$store_image"

if ! kubectl get secret "$postgres_secret" -n "$namespace" >/dev/null 2>&1; then
  password="$(openssl rand -hex 16)"
  database_url="postgresql://${postgres_username}:${password}@postgres:5432/${postgres_database}"
  {
    printf '%s\n' 'apiVersion: v1' 'kind: Secret' 'metadata:' "  name: $postgres_secret" "  namespace: $namespace" 'type: Opaque' 'stringData:'
    printf '  database: %s\n' "$postgres_database"
    printf '  username: %s\n' "$postgres_username"
    printf '  password: %s\n' "$password"
    printf '  url: %s\n' "$database_url"
  } | kubectl apply -f - >/dev/null
  unset password database_url
fi

printf 'Validando onboarding OTel e manifests...\n'
helm lint "$team_chart_dir" --values "$team_values"
helm template "$team_release" "$team_chart_dir" --namespace "$namespace" --values "$team_values" | kubectl apply --dry-run=server -f - >/dev/null
for directory in "${workload_dirs[@]}"; do
  kubectl kustomize "$directory" >/dev/null
  kubectl kustomize "$directory" | kubectl apply --dry-run=server -f - >/dev/null
done

printf 'Registrando o onboarding OTel do time...\n'
helm upgrade --install "$team_release" "$team_chart_dir" --namespace "$namespace" \
  --values "$team_values" --atomic --wait --timeout 3m --take-ownership

printf 'Aplicando PostgreSQL...\n'
kubectl apply -k "$postgres_dir"
kubectl rollout status statefulset/postgres -n "$namespace" --timeout=180s

for directory in "$catalog_dir" "$insights_dir" "$store_dir" "$traffic_dir"; do
  printf 'Aplicando %s...\n' "$(basename "$directory")"
  kubectl apply -k "$directory"
done

kubectl rollout restart deployment/catalog-java deployment/insights-python deployment/store-node deployment/traffic-generator -n "$namespace"
for deployment in catalog-java insights-python store-node traffic-generator; do
  kubectl rollout status "deployment/$deployment" -n "$namespace" --timeout=180s
done

kubectl get pods,services,pvc -n "$namespace"
printf '\nPromptLab pronto. Acesse com:\n'
printf 'kubectl port-forward -n %s service/store-node 3000:3000\n' "$namespace"
printf 'http://localhost:3000\n'
