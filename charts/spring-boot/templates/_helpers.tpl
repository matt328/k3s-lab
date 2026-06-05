{{/*
Return the workload name. By default, the release name is the app name so
existing Service DNS names and immutable Deployment selectors stay stable.
*/}}
{{- define "spring-boot.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "spring-boot.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "spring-boot.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "spring-boot.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spring-boot.fullname" . }}
{{- end -}}

{{- define "spring-boot.labels" -}}
helm.sh/chart: {{ include "spring-boot.chart" . }}
{{ include "spring-boot.selectorLabels" . }}
{{- with .Values.component }}
app.kubernetes.io/component: {{ . }}
{{- end }}
{{- with .Values.partOf }}
app.kubernetes.io/part-of: {{ . }}
{{- end }}
{{- with .Values.version }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "spring-boot.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "spring-boot.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "spring-boot.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- $digest := .Values.image.digest -}}
{{- if $digest -}}
{{- printf "%s:%s@%s" $repository $tag $digest -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}
