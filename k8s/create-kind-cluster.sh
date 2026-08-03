#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
values_file="$script_dir/values-local.yaml"

usage() {
  cat <<'EOF'
Uso: bash ./k8s/create-kind-cluster.sh

Cria (ou seleciona) o cluster Kind definido em k8s/values-local.yaml.
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
  local query="$1"
  local value
  value="$("$yq_bin" -r "$query" "$values_file" 2>/dev/null)" \
    || die "Valor obrigatorio '$query' ausente em $values_file."
  [[ -n "$value" && "$value" != "null" ]] || die "Valor obrigatorio '$query' ausente em $values_file."
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

require_command kind
require_command kubectl
resolve_yq
[[ -f "$values_file" ]] || die "Arquivo de configuracao nao encontrado: $values_file"

cluster_name="$(yaml_value '.cluster.name')"

if kind get clusters | grep -Fxq "$cluster_name"; then
  kubectl config use-context "kind-$cluster_name" >/dev/null
else
  kind create cluster --name "$cluster_name" --config "$script_dir/kind-cluster.yaml"
fi

kubectl get nodes
printf '\nCluster Kind ativo: kind-%s\n' "$cluster_name"
