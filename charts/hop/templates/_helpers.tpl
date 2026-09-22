{{/* Base name of every resource: the name value, else the Helm release name. */}}
{{- define "hop.name" -}}
{{- .Values.name | default .Release.Name -}}
{{- end -}}

{{- define "hop.credentialsSecret" -}}
{{- .Values.credentials.existingSecret | default (printf "%s-credentials" (include "hop.name" .)) -}}
{{- end -}}

{{- define "hop.serverService" -}}
{{- printf "%s-server" (include "hop.name" .) -}}
{{- end -}}

{{/* Reads the credentials once per render: several templates need the same
     generated password, and randAlphaNum returns a new one on every call.
     The value is kept in .Values, which every template shares. An existing
     Secret wins, so a generated password survives upgrades. */}}
{{- define "hop.loadCredentials" -}}
{{- if not (hasKey .Values "__credentials") -}}
{{- $creds := dict "username" .Values.credentials.username "password" "" -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "hop.credentialsSecret" .) -}}
{{- if $existing -}}
{{- $_ := set $creds "password" (index $existing.data "password" | default "" | b64dec) -}}
{{- if .Values.credentials.existingSecret -}}
{{- $_ := set $creds "username" (index $existing.data "username" | default "" | b64dec) -}}
{{- end -}}
{{- end -}}
{{- if and (not $creds.password) (not .Values.credentials.existingSecret) -}}
{{- $_ := set $creds "password" (randAlphaNum 24) -}}
{{- end -}}
{{- $_ := set .Values "__credentials" $creds -}}
{{- end -}}
{{- end -}}

{{- define "hop.password" -}}
{{- include "hop.loadCredentials" . -}}
{{- .Values.__credentials.password -}}
{{- end -}}

{{- define "hop.username" -}}
{{- include "hop.loadCredentials" . -}}
{{- .Values.__credentials.username -}}
{{- end -}}

{{/* oauth2-proxy cookie secret: 32 bytes, generated once. */}}
{{- define "hop.cookieSecret" -}}
{{- if not (hasKey .Values "__cookieSecret") -}}
{{- $value := "" -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (printf "%s-oauth2-proxy" (include "hop.name" .)) -}}
{{- if $existing -}}
{{- $value = index $existing.data "cookie-secret" | default "" | b64dec -}}
{{- end -}}
{{- $_ := set .Values "__cookieSecret" ($value | default (randAlphaNum 32)) -}}
{{- end -}}
{{- .Values.__cookieSecret -}}
{{- end -}}
