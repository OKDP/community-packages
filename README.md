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

## Structure

```
packages/
└── services/
    ├── ollama/
    ├── ollama-ui/
    └── rustfs/
charts/
└── oidc-dcr-cleanup/          # local chart, used by ollama-ui when OIDC DCR is enabled
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
