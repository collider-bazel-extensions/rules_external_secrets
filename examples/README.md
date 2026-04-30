# Examples

Reference `SecretStore` + `ExternalSecret` shapes. Apply them after
`external_secrets_install` has the operator + CRDs running.

| File | Use case | Exercised by smoke? |
|---|---|---|
| [`fake_store.yaml`](fake_store.yaml) | `fake` provider — data baked into the SecretStore CR. Designed for tests; what rules_external_secrets's smoke uses. | Yes |
| [`kubernetes_provider.yaml`](kubernetes_provider.yaml) | Cross-namespace sync — read source-of-truth Secret in another namespace. Common production pattern (no real backend needed). RBAC-scoped via ServiceAccount. | No (same operator code path as the fake-provider smoke; documenting for consumers) |
| [`vault_token.yaml`](vault_token.yaml) | HashiCorp Vault SecretStore via static token. Real production. | No (Vault fixture is deferred to v0.2) |

## Things this directory deliberately does NOT show

- **AWS Secrets Manager / GCP Secret Manager / Azure Key Vault providers.**
  Each backend has its own auth flow; they're documented in
  [ESO's docs](https://external-secrets.io/) and require credentials
  that don't belong in tests.
- **`PushSecret` (push-only — sync K8s Secret upward to a backend)**.
  v0.2 candidate.
- **`ClusterSecretStore` / `ClusterExternalSecret` (cluster-scoped variants)**.
  Same shape as the namespaced versions but cluster-scoped. The
  patterns above translate directly.
