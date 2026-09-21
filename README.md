# community-packages

KuboCD packages compatible with [OKDP](https://okdp.io), maintained by the community — services not
(yet) part of the official [`OKDP/platform-packages`](https://github.com/OKDP/platform-packages) catalog.

This repository follows the same conventions as `platform-packages`: it is **packages-only** — it
owns the package definitions under `packages/` and the CI that builds and publishes them as OCI
artifacts. Deployment (releases, contexts) belongs to the consuming environment, e.g.
[`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox) or a fork of it.

## Packages

| Package | Role | Notes |
|---|---|---|
| [`rustfs`](./packages/services/rustfs/rustfs.yaml) | S3-compatible object storage | Binds the OKDP `defaultStorage` provider contract |
| [`ollama`](./packages/services/ollama/ollama.yaml) | Local LLM inference server | CPU mode, no GPU; the model is a parameter |
| [`ollama-ui`](./packages/services/ollama-ui/ollama-ui.yaml) | Chat interface for `ollama` | Points at an `ollama` release in the same project |
| [`k8ssandra-operator`](./packages/system/k8ssandra-operator/k8ssandra-operator.yaml) | K8ssandra operator (Cassandra) | Installed once per platform, watches every namespace; needs cert-manager |
| [`k8ssandra`](./packages/services/k8ssandra/k8ssandra.yaml) | Apache Cassandra cluster | One datacenter, auth on; optional Reaper (repairs) and Medusa (backups to an `s3` Connection); needs `k8ssandra-operator` |

## Structure

```
packages/
├── system/                    # platform-wide, installed once (operators)
│   └── k8ssandra-operator/
└── services/
    ├── k8ssandra/
    ├── ollama/
    ├── ollama-ui/
    └── rustfs/
charts/
└── k8ssandra-cluster/         # local chart, the K8ssandraCluster deployed by k8ssandra
community-packages-values.yaml # OCI publish target (packageRepository), read by CI
```

## Registry layout

- **Publish path** (what releases consume, pushed by `publish.yml`, manually dispatched):
  `quay.io/okdp/community-packages/{package}:{tag}` — a published tag is immutable; bump the
  package's `tag` to publish a new version.
- **CI path** (throwaway validation builds on every push/PR, `ghcr.io`):
  `ghcr.io/okdp/community-packages/community-packages/{package}:{tag}`

Publishing to `quay.io` uses a dedicated robot account (`secrets.REGISTRY_USERNAME` /
`secrets.REGISTRY_ROBOT_TOKEN`, inherited from the OKDP organization). The CI path only needs the
workflow's own `GITHUB_TOKEN`.

## Building locally

```bash
kubocd package ./packages/services/rustfs/rustfs.yaml --ociRepoPrefix quay.io/okdp/community-packages
```

## License

[Apache License 2.0](./LICENSE). Portions of the CI tooling are adapted from `OKDP/platform-packages`.
