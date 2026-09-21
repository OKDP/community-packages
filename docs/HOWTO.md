# How to create an OKDP package

This guide walks through adding a new package to this repository, using the existing packages as
the reference. Read it alongside one of them:

- [`ollama`](../packages/services/ollama/ollama.yaml): the smallest one. One Helm chart, a few
  parameters, one ingress. **Start here.**
- [`ollama-ui`](../packages/services/ollama-ui/ollama-ui.yaml): adds OIDC single sign-on,
  including Dynamic Client Registration (DCR), and uses a local chart.
- [`rustfs`](../packages/services/rustfs/rustfs.yaml): the full feature set. UI form hints,
  `usage` text, extra manifests, a provisioning Job, `outputs` for a contract, and `roles` and
  `dependencies`.

A package is a [KuboCD](https://github.com/kubocd/kubocd) manifest. It wraps one or more Helm
charts, declares the parameters a user can set and the platform context it needs, and is
published as an OCI artifact. Deployment (Releases, Contexts) is **not** part of this repository.
That belongs to the consuming environment, e.g. [`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox).

## 1. Create the package directory

```
packages/services/<name>/<name>.yaml
```

- `<name>` is the package name. Use lowercase with hyphens. It becomes the OCI repository name:
  `quay.io/okdp/community-packages/<name>`.
- Put **exactly one** manifest with a top-level `modules:` key in the directory. CI and the
  release tooling find the package by grepping for `^modules:`, not by file name.
- Start the file with the Apache 2.0 license header copied from an existing package.

## 2. Write the header

```yaml
apiVersion: v1alpha1
name: myservice
tag: 2.3.1-1.0.0
description: |
  MyService: one line saying what it is.
  A second line on how it is deployed here (CPU only, needs X in the same project, ...).
```

### The tag

The tag always has two parts: `<upstream version>-<OKDP version>`.

| Part | Example | Owned by |
|---|---|---|
| upstream | `2.3.1` | You. Usually the chart or app version. Update it by hand when you bump the chart. |
| OKDP | `1.0.0` | release-please. It is derived from your commits (see [§8](#8-release)). |

Start a new package at `-1.0.0`. The OKDP half must be a plain `X.Y.Z` at the end of the tag.
[`compose-oci-tag.sh`](../.github/scripts/compose-oci-tag.sh) strips exactly one trailing
`-X.Y.Z` and treats everything to its left as the upstream half, so `1.3.0-incubating-1.0.0` also
works.

A published tag is **immutable**. The publish job refuses to overwrite an existing tag.

### Optional header fields

- `usage.text`: a templated text shown to the user after deployment (endpoints, first-run
  steps). See `rustfs`.
- `protected: false`: controls whether the Release can be deleted from the UI.

## 3. Declare the schema

`schema` has two sections. The template can only read what these declare.

### `schema.parameters`: what the user chooses

These are JSON-schema-like properties. Conventions used across the packages:

- **Give every parameter a `description`** that says what the value does and what it costs, e.g.
  memory needs per model size. It is the only help the user gets.
- **Resources.** Use these names so every package looks the same:

  | Parameter | Type | Rendered as |
  |---|---|---|
  | `cpu` | `number`, `multipleOf: 0.25` | request = `cpu`, limit = `cpu × 2` |
  | `memoryGi` | `number` (`multipleOf: 0.25` where fractions make sense) | request = limit = `memoryGi`Gi |
  | `storageGi` | `integer` | PVC size in Gi |

  ```yaml
  resources:
    requests:
      cpu: "{{ .Parameters.cpu }}"
      memory: "{{ .Parameters.memoryGi }}Gi"
    limits:
      cpu: "{{ mulf (float64 .Parameters.cpu) 2 }}"
      memory: "{{ .Parameters.memoryGi }}Gi"
  ```

  Choose a `memoryGi` default that actually runs the app, and explain why in the description or in
  a comment. `ollama-ui` needs 2 GiB because it loads an embedding model at startup and gets
  OOMKilled under 1 GiB.
- **Closed choices** use `enum` (see `ollama.model`, `ollama.gpuVendor`).
- **Secrets never get a default.** A default shipped in a package ends up in production. Mark
  the parameter `required: true` without a `default` (see `rustfs.rootSecretKey`).
- **Form hints (optional).** A `title` of the form `"Group | Label | | order:N columns:2 advanced:true"`
  lays out the parameter in the OKDP UI form (see `rustfs`).

### `schema.context`: what the platform provides

Declare **only** the context keys the template reads, and mark them `required: true` so a
misconfigured environment fails at render time instead of producing a broken deployment. The keys
the existing packages use:

| Key | Used for |
|---|---|
| `ingress.suffix` | DNS suffix of every ingress host |
| `certificateIssuers.selfSigned.name` | cert-manager `ClusterIssuer` for ingress TLS |
| `storageClass.workspace` | PVCs for application state (models, user data) |
| `storageClass.data` | PVCs for bulk data (object storage) |
| `oidc.issuerUri`, `oidc.enabled`, `oidc.displayName`, `oidc.scope`, `oidc.clientProvisioning`, `oidc.dcr.*` | Single sign-on (see [§5](#5-single-sign-on-oidc)) |

Copy the `oidc` block from an existing package as-is so that all packages share the same
defaults.

## 4. Write the modules

Each module installs one Helm chart. The service itself is the module named `main`.

```yaml
modules:
  - name: main
    timeout: 10m          # raise it for slow starts, e.g. ollama uses 15m to pull a model
    source:
      helmRepository:
        url: https://charts.example.com/
        chart: myservice
        version: 2.3.1    # keep in sync with the upstream half of the tag
    values: |
      ...
```

A chart can come from one of three sources:

| Source | Example |
|---|---|
| `helmRepository: { url, chart, version }` | `ollama`, `ollama-ui`, `rustfs` main modules |
| `oci: { repository, tag }` | `quay.io/adaltas/oidc-dcr` |
| `local: { path }` | `../../../charts/oidc-dcr-cleanup`. The path is relative to the manifest. Put shared charts under [`charts/`](../charts). |

A module can be switched on or off with `enabled:`, a template that must render to `true` or
`false`.

### Templating `values`

`values` is a Go template with Sprig functions. It renders to the chart's values. These objects
are available:

| Object | Content |
|---|---|
| `.Parameters.*` | The user's parameters, with defaults applied |
| `.Context.*` | The platform context |
| `.Release.metadata.name` | The Release name |
| `.Release.spec.targetNamespace` | The namespace (the OKDP project) |

Set up your variables at the top of the block with `{{- ... -}}` so they emit no blank lines, and
add a comment on any expression that is not obvious.

### Ingress host convention

All packages build hosts the same way: `<release without its project prefix>-<project>.<suffix>`.
The console prefixes instance names with the project, so without the `trimPrefix` the namespace
would appear twice in the host.

```yaml
{{- $ns := .Release.spec.targetNamespace -}}
{{- $host := printf "%s-%s.%s" (trimPrefix (printf "%s-" $ns) .Release.metadata.name) $ns .Context.ingress.suffix -}}
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: "{{ .Context.certificateIssuers.selfSigned.name }}"
  hosts:
    - host: {{ $host }}
      paths: [{ path: /, pathType: Prefix }]
  tls:
    - hosts: [{{ $host }}]
      secretName: {{ .Release.metadata.name }}-tls
```

Derive every name (hosts, Secrets, Services) from the Release name, never from the product name.
Two instances in the same project must not collide.

### Things the chart does not do

If the upstream chart is missing something (a second ingress, a provisioning Job), add it through
the chart's `extraManifests` or equivalent value when there is one. `rustfs` uses this for its S3
ingress and for a post-install Job that creates buckets, users and policies. If the chart has no
such value, write a small local chart under `charts/` and add it as another module.

## 5. Single sign-on (OIDC)

Web UIs should sign in through the platform's identity provider. The pattern below is shared by
`ollama-ui` and `rustfs`. Copy it rather than reinventing it.

**Is SSO on?** `oidc.enabled` defaults to true. Read it with `hasKey`, because
`false | default true` is `true` in Sprig:

```yaml
{{- $oidcEnabled := true -}}
{{- if hasKey .Context.oidc "enabled" }}{{- $oidcEnabled = .Context.oidc.enabled -}}{{ end -}}
```

**Where are the client credentials?** It depends on `oidc.clientProvisioning`:

| Mode | Secret | Keys |
|---|---|---|
| `existing` (default) | `creds-<release>-oauth2`, created by the platform | `client_id`, `client_secret` |
| `dcr` | `<release>-<namespace>-dcr`, written by the `oidc-dcr` module | same keys |

In `dcr` mode, add two modules before `main`. Copy them from `ollama-ui` and change only the
`redirect_uris`:

- `oidc-dcr` (`quay.io/adaltas/oidc-dcr`) registers the client anonymously on install.
- `oidc-dcr-cleanup` (the local [`charts/oidc-dcr-cleanup`](../charts/oidc-dcr-cleanup))
  unregisters it and deletes the Secret on uninstall.

Both use this `enabled:` expression:

```yaml
enabled: '{{ and (ne (.Context.oidc.enabled | toString) "false") (eq (.Context.oidc.clientProvisioning | default "existing") "dcr") }}'
```

Module values are rendered even when the module is disabled, so guard anything that would fail
(for example the `authMethod` check in the `oidc-dcr` values).

**Trusting the provider.** The platform's issuer uses a private CA. Mount the `ca.crt` of the
Secret named by a `caBundleSecret` parameter (default `certs-bundle`) and point the app at it
(`SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, ...).

**Roles.** Map token claims to application roles through parameters with sensible defaults
(`oidcRolesClaim`, `oidcAllowedRoles`, `oidcAdminRoles` in `ollama-ui`). Do not hard-code them.

## 6. Outputs, roles and dependencies (optional)

These fields matter when the package plugs into other packages. See `rustfs`.

- `outputs`: a templated list of connections the package produces. Each has a `name`, the
  `contract` it satisfies (e.g. `s3`), and the `values` that contract defines (URLs, region, ...).
  Consumers bind to the contract, not to the package, which is why `rustfs` can serve as the
  platform's `defaultStorage`.
- `roles`: the platform roles this package can fill (e.g. `storage`).
- `dependencies`: roles that must be deployed first (e.g. `ingress`).

## 7. Register the package and test it

### Register it with release-please

Add the directory to **both** files.

[`release-please-config.json`](../release-please-config.json), under `packages`:

```json
"packages/services/myservice": {
  "component": "myservice",
  "release-type": "simple",
  "include-component-in-tag": true,
  "tag-separator": "/",
  "changelog-path": "CHANGELOG.md"
}
```

[`.release-please-manifest.json`](../.release-please-manifest.json):

```json
"packages/services/myservice": "1.0.0"
```

The manifest version must match the OKDP half of the `tag`.

Also add a row to the package table in the [README](../README.md).

### Build locally

You need `kubocd` v0.3.2 or later (the version CI installs).

```bash
# Inspect the package as KuboCD parses it, into ./.dump/<name>/ (add --charts to fetch the charts too)
kubocd dump package ./packages/services/myservice/myservice.yaml

# Build it and push it to a registry you can write to
kubocd package ./packages/services/myservice/myservice.yaml --ociRepoPrefix <registry>/<your-namespace>
```

To check the rendered chart values, write a throwaway Release manifest that points at your
package and run `kubocd render <release.yaml> ./packages/services/myservice/myservice.yaml`. It
reads the KuboCD configuration and contexts from the current cluster.

### CI

Every push and pull request (except changes limited to docs) builds every package and pushes it
to the CI registry:

```
ghcr.io/okdp/community-packages/community-packages/<name>:0.0.0-ci.<branch>.g<sha>
```

That tag is unique to the build, so you can pin it in a sandbox Release to try the branch on a
real cluster before merging. Nothing is published to `quay.io` from a pull request.

## 8. Release

Pull request titles and commits must follow
[Conventional Commits](https://www.conventionalcommits.org/). CI checks this. release-please
assigns each commit to a package by the **path** it touches, and bumps that package's OKDP
version:

| Commit | Bump | When |
|---|---|---|
| `fix: ...` | patch | Bug fix, no change for users |
| `feat: ...` | minor | New parameter or feature, backward compatible |
| `feat!: ...` / `BREAKING CHANGE:` | major | Parameter renamed or removed, new required context key, ... |

Use `feat: add <name> package` for a new package.

After merge, release-please keeps one draft release pull request open. It updates the versions in
`.release-please-manifest.json`, the changelogs, and (through `compose-oci-tag.sh`) the `tag:` line
of each manifest. Merging that pull request tags `<name>/v<version>` and publishes the released
packages to `quay.io/okdp/community-packages/<name>:<tag>`.

Do not edit the OKDP half of `tag:` by hand. Edit the upstream half when you bump the chart, in
the same commit as `version:`. The next release keeps it.

The first release of a new package is the version after the one in the manifest (e.g. `1.1.0`
after a `feat:`). To publish the initial `-1.0.0` tag itself, a maintainer can run the manual
`publish` workflow. It publishes every tag that is not yet on the registry.

## Checklist

- [ ] `packages/services/<name>/<name>.yaml`, license header, one `modules:` manifest
- [ ] `tag: <upstream>-1.0.0`, and the chart `version` matches the upstream half
- [ ] Every parameter has a `description`, `cpu`/`memoryGi`/`storageGi` follow the conventions,
      and no secret has a default
- [ ] Only the context keys you read are declared, marked `required: true`
- [ ] Hosts, Secrets and Services are derived from the Release name, and ingress hosts follow the
      `<release>-<project>.<suffix>` convention with TLS from the platform issuer
- [ ] SSO follows the shared OIDC pattern (both `existing` and `dcr`), if the app has a UI
- [ ] Added to `release-please-config.json`, `.release-please-manifest.json` and the README table
- [ ] `kubocd package` succeeds locally, and CI is green
- [ ] Conventional commit: `feat: add <name> package`
