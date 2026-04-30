"""Public API for rules_external_secrets.

Two macros wrapping rules_kubectl's `kubectl_apply` /
`kubectl_apply_health_check` with ESO-specific defaults.
"""

load("@rules_kubectl//:defs.bzl", "kubectl_apply", "kubectl_apply_health_check")

# The chart deploys three components (operator, webhook, cert-controller).
# Names are `<release>` and `<release>-{webhook,cert-controller}`; we
# pin release name to `external-secrets` at maintainer-render time so the
# Deployment names below match. The CRD wait is load-bearing: without it,
# downstream services applying ExternalSecret CRs immediately after install
# would race the operator's CRD installer.
_ESO_DEPLOYS = [
    "external-secrets",
    "external-secrets-webhook",
    "external-secrets-cert-controller",
]
_ESO_CRD = "externalsecrets.external-secrets.io"

def external_secrets_install(
        name,
        namespace = "external-secrets",
        wait_timeout = "300s",
        **kwargs):
    """Apply the pinned ESO manifest into `namespace` and block until the
    three Deployments are Available + the ExternalSecret CRD is registered.

    Drops into `itest_service.exe`.

    Args:
      name: target name.
      namespace: target namespace. Pre-created idempotently. Default
        `external-secrets`.
      wait_timeout: per-wait timeout. Default 300s.
      **kwargs: forwarded to `kubectl_apply` (e.g. `tags`, extra waits).
    """
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply(
        name = name,
        manifests = ["@rules_external_secrets//private/manifests:external_secrets.yaml"],
        namespace = namespace,
        create_namespace = True,
        server_side = True,
        wait_for_deployments = list(_ESO_DEPLOYS) + list(extra_deploys),
        wait_for_crds = [_ESO_CRD] + list(extra_crds),
        wait_timeout = wait_timeout,
        **kwargs
    )

def external_secrets_health_check(
        name,
        namespace = "external-secrets",
        **kwargs):
    """Readiness probe paired with `external_secrets_install`.

    Drops into `itest_service.health_check`.
    """
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply_health_check(
        name = name,
        namespace = namespace,
        wait_for_deployments = list(_ESO_DEPLOYS) + list(extra_deploys),
        wait_for_crds = [_ESO_CRD] + list(extra_crds),
        **kwargs
    )
