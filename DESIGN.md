# rules_external_secrets — design decisions

Hermetic [External Secrets Operator](https://external-secrets.io/) (ESO)
install for Bazel test compositions. Same shape as `rules_loki` /
`rules_grafana` / `rules_harbor` — pure glue over `rules_kubectl` +
`rules_helm`.

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod-only at v0.1.** | Sibling-family |
| 2 | Module / repo name | `rules_external_secrets` (snake_case). Bzlmod doesn't allow hyphens in module names; matching the sibling rule sets' convention. | Bzlmod constraint + convention |
| 3 | Architecture | **Layered.** Two macros wrapping `kubectl_apply` / `kubectl_apply_health_check`. | rules_loki / rules_grafana / rules_harbor |
| 4 | Manifest provisioning | ESO helm chart **pre-rendered** into `private/manifests/external_secrets.yaml` via `rules_helm`. Committed. | rules_loki pattern |
| 5 | Single-version | One pinned chart (`2.4.1`, ESO app `v2.4.1`). Multi-version is the rules_cloudnativepg pattern; add it if a real consumer wants two versions side-by-side. | Pragmatic |
| 6 | Render mode | **Smoke fixture.** `replicaCount: 1`, monitoring sidecars off, bitwarden-sdk-server subchart off, leader election off. README warns the values are not a production starting point. | Smoke pragmatic |
| 7 | Public surface | `external_secrets_install`, `external_secrets_health_check`. **No `external_secrets_secret_store` rule** — SecretStore CRs are 5+ provider variants × auth flavors; v0.1 documents the YAML pattern + ships `examples/`. | Smaller surface |
| 8 | Namespace | `external-secrets` (default, idempotent create). | Convention |
| 9 | Wait shape | 3 Deployments (`external-secrets`, `external-secrets-webhook`, `external-secrets-cert-controller`) + the `externalsecrets.external-secrets.io` CRD. The CRD wait is load-bearing — same race-against-CRD-installer lesson rules_argocd / rules_cloudnativepg taught. | ESO-specific |
| 10 | Smoke backend | **`fake` provider.** ESO ships a built-in `fake` SecretStore type designed for testing — data baked into the SecretStore CR's spec. No external backend, no real Vault / AWS / GCP, no extra in-cluster fixture pod. | Smallest hermetic round-trip |
| 11 | Smoke assertion | Apply SecretStore (fake provider, unique payload baked in) + ExternalSecret. Wait for the resulting K8s Secret. Decode the secret's data field and assert it matches the baked payload. Also verify ExternalSecret's `Ready=True` condition. Proves the operator's reconcile loop + provider resolution + data sync all work — **not** "ESO pods are up." | Per the family's "exercise the functionality" rule |
| 12 | Cross-rule deps | `rules_kubectl` public dep. `rules_helm` + `rules_kind` + `rules_itest` + `rules_shell` dev-only. No cert-manager required (chart self-signs the webhook cert). | rules_loki precedent |
| 13 | Naming | snake_case rules/macros, `MixedCaseInfo` providers (none in v0.1), `UPPER_SNAKE` constants. | All siblings |
| 14 | Update workflow | `bash tools/render_eso.sh <chart-version>` → thin shim. | rules_loki precedent |

## ESO-specific notes

- ESO chart 2.x is the current major. The chart's appVersion + chart version moved together at v2.0; older `v0.x` charts are end-of-life. Pin recent.
- The chart deploys 3 Deployments by default. Disabling the webhook (`webhook.create: false`) removes one but breaks defaulting on ExternalSecret CRs — keep all three on.
- The `fake` provider's data is part of the SecretStore CR's spec — ESO reads it from the CR rather than reaching out to a remote system. Designed for tests; documented in ESO's [provider list](https://external-secrets.io/main/provider/fake/).
- ExternalSecret CRD is `external-secrets.io/v1beta1`. ESO's `v1` is being introduced gradually but `v1beta1` remains the stable surface for v2.x charts. The smoke + examples use `v1beta1`.
- Chart has a `bitwarden-sdk-server` subchart (gated on `.enabled: false` by default — explicitly pinned off in our values file).

## v0.1.0 status (planning)

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only) | planned |
| `external_secrets_install` + `external_secrets_health_check` macros | planned |
| Pinned ESO chart 2.4.1 (rendered + committed) | planned |
| `config/eso-values.yaml` (exported) | planned |
| Maintainer render flow | planned |
| Analysis test | planned |
| Smoke (kind + ESO + fake-provider SecretStore + payload round-trip) | planned |
| `examples/` (fake-provider, kubernetes provider, Vault sketch) | planned |

## Deferred (not v0.1.0)

- **Vault smoke** — compose with an in-cluster Vault dev-mode pod. v0.2 candidate; would also fit a `rules_vault` if that rule set ever exists.
- **AWS / GCP / Azure provider smokes** — each backend has its own auth flow + would need fixtures (LocalStack for AWS, etc.) plus credentials we don't want in tests.
- **`PushSecret` smoke** — the inverse direction (push K8s Secret upward to a backend).
- **`ClusterSecretStore` / `ClusterExternalSecret`** — cluster-scoped variants. Same shape, different scope. Document in examples/ later.
- **Multi-version chart support** — single pin in v0.1.
- **HA / multi-replica smoke** — would need fault injection to be meaningful.
- **`generators` smoke** — ESO generators (`Password`, `ECRAuthorizationToken`, etc.) generate values rather than fetching them. Different code path; v0.2 candidate.
