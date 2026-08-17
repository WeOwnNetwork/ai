# Policy template: svc-platform-<service>   (locked §2.3)
# Read-only on exactly one platform service's secret subtree. Bound to that
# service's AppRole. Substitute {{SERVICE}} (e.g. sso-keycloak, billing, hermes).
#
# Rendered name MUST equal the AppRole name MUST equal the register row (§2.1).

path "weown/data/platform/{{SERVICE}}/*" {
  capabilities = ["read"]
}

# KV-v2 metadata is needed to list versions; read-only, same leaf.
path "weown/metadata/platform/{{SERVICE}}/*" {
  capabilities = ["read", "list"]
}
