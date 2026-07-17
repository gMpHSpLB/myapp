{{/*
Expand the name of the chart.
Usage: {{ include "myapp.name" . }}
*/}}
{{- define "myapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a fully qualified app name.
Combines release name with chart name unless nameOverride is set.
Truncated to 63 chars — Kubernetes label value limit.
Usage: {{ include "myapp.fullname" . }}
*/}}
{{- define "myapp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart label: "myapp-1.0.0" — identifies which chart version created this resource.
Usage: {{ include "myapp.chart" . }}
*/}}
{{- define "myapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Standard labels applied to EVERY resource this chart creates.
These are the labels Helm uses to track ownership.
Usage: {{ include "myapp.labels" . | nindent 4 }}
*/}}
{{- define "myapp.labels" -}}
helm.sh/chart: {{ include "myapp.chart" . }}
{{ include "myapp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — used by Deployment selector and Service selector.
These MUST be stable. Changing them requires deleting and recreating the Deployment.
Usage: {{ include "myapp.selectorLabels" . | nindent 6 }}
*/}}
{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
Usage: {{ include "myapp.serviceAccountName" . }}
*/}}
{{- define "myapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "myapp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image string: combines repository, name, and tag.
Allows overriding each part independently.
Usage: {{ include "myapp.image" . }}
*/}}
{{- define "myapp.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}

{{/*
Environment-specific resource name prefix.
Used to differentiate dev/staging/prod resources in shared clusters.
Usage: {{ include "myapp.envPrefix" . }}
*/}}
{{- define "myapp.envPrefix" -}}
{{- printf "%s-%s" (include "myapp.fullname" .) .Values.environment }}
{{- end }}

{{- define "myapp.configmapChecksum" -}}
{{ toYaml .Values.config | sha256sum }}
{{- end -}}

{{- define "myapp.secretChecksum" -}}
{{ toYaml .Values.secrets | sha256sum }}
{{- end -}}