# Policy template: svc-agency-<agency>-<platform>-<instance>   (locked §2.3)
# Read-only on exactly ONE agency instance's secret subtree. Bound to that
# instance's AppRole. Substitute {{AGENCY}} {{PLATFORM}} {{INSTANCE}}
# (e.g. volcarian / chat / prod).
#
# Cross-agency reads are structurally impossible: no template spans two
# {{AGENCY}} values, so a compromised instance reads its own secrets and nothing
# else (§2.1 principle 1).

path "weown/data/agency/{{AGENCY}}/{{PLATFORM}}/{{INSTANCE}}/*" {
  capabilities = ["read"]
}

path "weown/metadata/agency/{{AGENCY}}/{{PLATFORM}}/{{INSTANCE}}/*" {
  capabilities = ["read", "list"]
}
