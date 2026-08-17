# Policy: secrets-admin   (locked §2.3 — NOT a template, one policy)
# Policy/auth/mount administration for named humans via OIDC. Deliberately holds
# NO blanket data read: an admin manages the store's shape, they do not get to
# read every tenant's secrets by virtue of being an admin (§2.3 hard rule).
# The root token is sealed away after setup; this is how humans administer.

path "sys/policies/acl/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/auth"           { capabilities = ["read", "list"] }
path "sys/auth/*"         { capabilities = ["create", "read", "update", "delete", "sudo"] }
path "auth/approle/role/*"{ capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/mounts"         { capabilities = ["read", "list"] }
path "sys/mounts/*"       { capabilities = ["create", "read", "update", "delete", "sudo"] }
path "identity/*"         { capabilities = ["create", "read", "update", "delete", "list"] }

# Explicitly NO `weown/data/*` grant. An admin who needs a value uses an
# operator role too — separation is the point.
