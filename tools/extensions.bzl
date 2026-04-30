"""Maintainer-only chart fetch — fires only when rules_external_secrets is the root."""

load("//tools:repositories.bzl", "eso_chart_repository")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            eso_chart_repository(
                name = "eso_chart_" + tag.version.replace(".", "_"),
                version = tag.version,
            )

eso_chart = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
