#!/usr/bin/env bash
# Secret round-trip smoke. Apply a SecretStore (fake provider, with a
# unique payload baked into its spec) + an ExternalSecret. ESO's
# reconciler should read the SecretStore's data, materialize a regular
# K8s Secret, and keep refreshing it. We wait for the Secret, decode
# the value, and assert it matches the baked payload.
#
# Proves: the operator's reconcile loop + SecretStore provider
# resolution + ExternalSecret data sync all work end-to-end. Not "ESO
# pods are up." The `fake` provider keeps the smoke hermetic — no
# Vault, no AWS, no GCP creds, no extra fixtures.
set -euo pipefail

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")

NS="smoke"
PAYLOAD="rules_external_secrets-smoke-$RANDOM-$(date +%s)"
SECRET="my-k8s-secret"
SECRET_KEY="api-key"

echo "smoke_test: applying SecretStore (fake provider) + ExternalSecret"
"${KCTL[@]}" apply -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${NS}
---
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: fake-store
  namespace: ${NS}
spec:
  provider:
    fake:
      data:
        - key: my-secret/${SECRET_KEY}
          value: "${PAYLOAD}"
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-external-secret
  namespace: ${NS}
spec:
  refreshInterval: 5s
  secretStoreRef:
    name: fake-store
    kind: SecretStore
  target:
    name: ${SECRET}
  data:
    - secretKey: ${SECRET_KEY}
      remoteRef:
        key: my-secret/${SECRET_KEY}
EOF

# ESO reconciles ExternalSecrets on its `refreshInterval` (5s above) +
# initial reconcile after the CR is created. Poll for the Secret to
# materialize, with a 90s ceiling.
echo "smoke_test: waiting for Secret/${SECRET} to materialize"
deadline=$(( $(date +%s) + 90 ))
while (( $(date +%s) < deadline )); do
  if "${KCTL[@]}" -n "$NS" get secret "$SECRET" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
"${KCTL[@]}" -n "$NS" get secret "$SECRET" >/dev/null \
  || { echo "smoke_test: FAIL — Secret/${SECRET} never materialized" >&2; \
       "${KCTL[@]}" -n "$NS" get externalsecret my-external-secret -o yaml >&2 || true; \
       exit 1; }

echo "smoke_test: decoding the Secret's '${SECRET_KEY}' field"
GOT=$("${KCTL[@]}" -n "$NS" get secret "$SECRET" \
    -o jsonpath="{.data.${SECRET_KEY}}" | base64 -d)

if [[ "$GOT" != "$PAYLOAD" ]]; then
  echo "smoke_test: FAIL — payload didn't round-trip" >&2
  echo "  expected: '$PAYLOAD'" >&2
  echo "  got:      '$GOT'" >&2
  "${KCTL[@]}" -n "$NS" get externalsecret my-external-secret -o yaml >&2 || true
  exit 1
fi

# Also verify the ExternalSecret's status condition reports synced. ESO
# sets `SecretSynced=True` on the CR's `.status.conditions` once the
# data has been pushed to the target Secret successfully.
synced=$("${KCTL[@]}" -n "$NS" get externalsecret my-external-secret \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [[ "$synced" != "True" ]]; then
  echo "smoke_test: FAIL — ExternalSecret status.Ready != True (got '$synced')" >&2
  "${KCTL[@]}" -n "$NS" get externalsecret my-external-secret -o yaml >&2 || true
  exit 1
fi

echo "smoke_test: OK — ExternalSecret synced, K8s Secret carries the baked payload"
