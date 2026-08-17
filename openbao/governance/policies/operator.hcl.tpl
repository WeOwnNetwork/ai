# Policy template: operator-<area>   (locked §2.3)
# CRUD on ONE tier subtree, for HUMANS via an OIDC group (never an AppRole).
# Substitute {{TIER}} (platform | agency/<agency> | infra) — a whole tier, or an
# agency subtree, but NEVER weown/data/* (that grant is illegal, §2.3 hard rule).
#
# e.g. operator-agency-volcarian -> {{TIER}} = agency/volcarian

path "weown/data/{{TIER}}/*" {
  capabilities = ["create", "read", "update", "delete"]
}
path "weown/metadata/{{TIER}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
# Let an operator see what exists without reading values.
path "weown/metadata/{{TIER}}" {
  capabilities = ["list"]
}
