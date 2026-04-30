# rules_external_secrets

Hermetic [External Secrets Operator](https://external-secrets.io/) (ESO)
install for Bazel test compositions. Pure glue layer over
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl) —
`external_secrets_install` is a macro emitting a `kubectl_apply` target
pre-configured with ESO's pinned manifest and the right wait shape.

```python
load("@rules_external_secrets//:defs.bzl",
     "external_secrets_install", "external_secrets_health_check")

external_secrets_install(name = "eso_install_bin")          # default ns: external-secrets
external_secrets_health_check(name = "eso_health_bin")
```

That's the whole API. ESO syncs secrets from external backends (Vault,
AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, the `kubernetes`
cross-namespace provider, and more) into Kubernetes `Secret` resources;
this rule set installs the operator. SecretStore + ExternalSecret CRs
are consumer-authored YAML — see [`examples/`](examples/).

**Pinned versions:** ESO helm chart `2.4.1` (ESO app `v2.4.1`).
Smoke-fixture render — single-replica, monitoring off, bitwarden-sdk-server
subchart off. The values file is exported as
`@rules_external_secrets//config:eso-values.yaml` for inspection /
extension.

**Supported platforms (v0.1):** any platform where rules_kubectl runs.
Validated on Linux x86\_64 in CI.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Defining SecretStores + ExternalSecrets](#defining-secretstores--externalsecrets)
- [Macros](#macros)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Contributing](#contributing)

---

## Installation

```python
bazel_dep(name = "rules_external_secrets", version = "0.1.0")
```

Bzlmod-only. Transitively pulls in
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl).

---

## Quickstart

```python
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_external_secrets//:defs.bzl",
     "external_secrets_install", "external_secrets_health_check")
load("@rules_kubectl//:defs.bzl", "kubectl_apply")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# 1. Cluster.
kind_cluster(name = "cluster", k8s_version = "1.32")
kind_health_check(name = "cluster_health", cluster = ":cluster")
itest_service(name = "kind_svc", exe = ":cluster", health_check = ":cluster_health")

# 2. ESO operator.
external_secrets_install(name = "eso_install_bin")
external_secrets_health_check(name = "eso_health_bin")
sh_binary(name = "eso_install_wrapper", srcs = ["install_wrapper.sh"], data = [":eso_install_bin"])
sh_binary(name = "eso_health_wrapper",  srcs = ["health_wrapper.sh"],  data = [":eso_health_bin"])

itest_service(
    name = "eso_svc",
    exe = ":eso_install_wrapper",
    deps = [":kind_svc"],
    health_check = ":eso_health_wrapper",
)

# 3. The actual SecretStore + ExternalSecret — your YAML.
kubectl_apply(
    name = "secrets_install_bin",
    manifests = ["my_secrets.yaml"],
)
sh_binary(name = "secrets_install_wrapper", srcs = ["install_wrapper.sh"], data = [":secrets_install_bin"])

itest_service(
    name = "secrets_svc",
    exe = ":secrets_install_wrapper",
    deps = [":eso_svc"],   # waits for operator + CRDs before applying SecretStore CRs
    # ...
)
```

`install_wrapper.sh` / `health_wrapper.sh` are ~20-line shims — see
`tests/install_wrapper.sh` for the canonical shape (sources kind's env
file under `set -a`, exec's the rule binary).

---

## Defining SecretStores + ExternalSecrets

`rules_external_secrets` deliberately does NOT ship `external_secrets_secret_store`
or `external_secrets_external_secret` Bazel rules. ESO supports 15+
providers × multiple auth flavors each; a v0.1 macro would either
flatten everything (becomes a YAML translator) or hide most. **Author
your CRs as YAML and apply via `kubectl_apply`.**

The simplest in-cluster pattern (and what `tests/smoke_test.sh` uses):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata: {name: fake-store, namespace: app}
spec:
  provider:
    fake:                       # built-in test provider
      data:
        - key: my-app/api-key
          value: "test-value"
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: {name: my-secret, namespace: app}
spec:
  refreshInterval: 30s
  secretStoreRef: {name: fake-store, kind: SecretStore}
  target: {name: my-k8s-secret}
  data:
    - secretKey: api-key
      remoteRef: {key: my-app/api-key}
```

For real backends (Vault, the `kubernetes` cross-namespace provider, AWS
Secrets Manager), see [`examples/`](examples/).

---

## Macros

### `external_secrets_install`

```python
external_secrets_install(
    name = "eso_install_bin",
    namespace = "external-secrets",   # default
    wait_timeout = "300s",            # default
)
```

Expands to a `kubectl_apply(...)` target that:

- Applies `@rules_external_secrets//private/manifests:external_secrets.yaml`.
- `create_namespace = True` (default `external-secrets`).
- `server_side = True`.
- `wait_for_deployments = ["external-secrets", "external-secrets-webhook", "external-secrets-cert-controller"]`.
- `wait_for_crds = ["externalsecrets.external-secrets.io"]` — load-bearing:
  prevents downstream services from racing the CRD installer.

Drops into `itest_service.exe`.

### `external_secrets_health_check`

```python
external_secrets_health_check(name = "eso_health_bin", namespace = "external-secrets")
```

Drops into `itest_service.health_check`. Same wait shape with
`--timeout=0s`.

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| ESO manifest | Fully hermetic. URL + sha256 pinned in `tools/versions.bzl`; pre-rendered + committed. | Re-render via `bash tools/render_eso.sh <ver>`. |
| `kubectl` | Inherited from `rules_kubectl`. | |
| Target cluster | Out of scope. | |
| ESO container images | Pulled at runtime by the cluster's nodes. | Future: pre-load via `kind_cluster.images`. |

---

## Contributing

PRs welcome. Conventions match the sibling rule sets:

- New rules need an analysis test in `tests/analysis_tests.bzl`.
- Bumping the pinned chart version: edit `tools/versions.bzl`, add a
  `helm_template + sh_binary` block in `tools/BUILD.bazel`, run
  `bash tools/render_eso.sh <new-version>`, commit.
- `MODULE.bazel.lock` is intentionally not committed.

### Help wanted

- macOS validation
- Vault provider smoke (compose with an in-cluster Vault dev-mode pod)
- `PushSecret` smoke (push K8s Secret upward to a backend)
- `ClusterSecretStore` / `ClusterExternalSecret` examples
- AWS Secrets Manager provider via LocalStack fixture
