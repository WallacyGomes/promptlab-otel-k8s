{{/* Valida o contrato de OTel do workload que chama esta biblioteca. */}}
{{- define "otel-workload.validate" -}}
{{- $otel := .otel | default (dict) -}}
{{- $enabled := default false (index $otel "enabled") -}}
{{- if $enabled -}}
  {{- range $key := list "instrumentationName" "language" "serviceName" "serviceVersion" "environment" "criticality" "time" -}}
    {{- if not (and (hasKey $otel $key) (ne (trim (toString (index $otel $key))) "")) -}}
      {{- fail (printf "observability.otel.%s e obrigatorio quando observability.otel.enabled=true" $key) -}}
    {{- end -}}
  {{- end -}}
  {{- $language := index $otel "language" -}}
  {{- if not (has $language (list "java" "nodejs" "python")) -}}
    {{- fail (printf "observability.otel.language=%q nao e suportada; use java, nodejs ou python" $language) -}}
  {{- end -}}
  {{- $criticality := index $otel "criticality" -}}
  {{- if not (has $criticality (list "critical" "high" "medium" "low")) -}}
    {{- fail (printf "observability.otel.criticality=%q nao e valida" $criticality) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Recebe:
  root: contexto raiz do chart de aplicacao
  otel: mapa observability.otel do workload
  podAnnotations: annotations adicionais do Pod
*/}}
{{- define "otel-workload.podAnnotations" -}}
{{- $root := .root -}}
{{- $otel := .otel | default (dict) -}}
{{- $podAnnotations := .podAnnotations | default (dict) -}}
{{- include "otel-workload.validate" (dict "otel" $otel) -}}
{{- $annotations := dict -}}
{{- range $key, $value := $podAnnotations -}}
  {{- if or (hasPrefix "instrumentation.opentelemetry.io/" $key) (hasPrefix "resource.opentelemetry.io/" $key) -}}
    {{- fail (printf "podAnnotations.%s usa um prefixo reservado pelo otel-workload" $key) -}}
  {{- end -}}
  {{- $_ := set $annotations $key (toString $value) -}}
{{- end -}}
{{- if (default false (index $otel "enabled")) -}}
  {{- $language := index $otel "language" -}}
  {{- $_ := set $annotations (printf "instrumentation.opentelemetry.io/inject-%s" $language) (toString (index $otel "instrumentationName")) -}}
  {{- $_ := set $annotations "resource.opentelemetry.io/service.name" (toString (index $otel "serviceName")) -}}
  {{- $_ := set $annotations "resource.opentelemetry.io/service.namespace" $root.Release.Namespace -}}
  {{- $_ := set $annotations "resource.opentelemetry.io/service.version" (toString (index $otel "serviceVersion")) -}}
  {{- $_ := set $annotations "resource.opentelemetry.io/service.criticality" (toString (index $otel "criticality")) -}}
  {{- $_ := set $annotations "resource.opentelemetry.io/deployment.environment.name" (toString (index $otel "environment")) -}}
  {{- $_ := set $annotations "resource.opentelemetry.io/tags.time" (toString (index $otel "time")) -}}
{{- end -}}
{{- toYaml $annotations -}}
{{- end -}}
