# ownCloud-Docker Security Model

## Overview

This document defines the security architecture for ownCloud Infinite Scale (oCIS) deployments, including state management, backup encryption, and access controls.

## Threat Model

### Actors

- **Developers**: Need to deploy and manage infrastructure
- **Operators**: Need to monitor and maintain running systems
- **Executives**: Need access to backups and disaster recovery
- **Attackers**: May gain access to developer machines or repositories

### Assets

- Terraform state files (contain infrastructure details)
- Application backups (contain user data)
- Encryption keys (protect backups and state)
- SSH keys (provide server access)

## Security Principles

### 1. Defense in Depth

- Multiple layers of protection
- No single point of failure
- Assume breach mentality

### 2. Least Privilege

- Developers can deploy but not decrypt backups
- Operators can monitor but not access sensitive data
- Executives can recover but not modify running systems

### 3. Separation of Duties

- Encryption keys held by executives
- Deployment access by developers
- Backup access restricted

## State File Security

### Storage

- **Location**: DigitalOcean Spaces (`weown-dev-backup` bucket)
- **Path**: `{project}/{project}.tfstate`
- **Encryption**: SSE-C with executive-held keys

### Naming Convention

```
weown-dev-backup/
├── sso/
│   └── sso.tfstate              # Keycloak SSO state
├── wordpress/
│   ├── burnedout-xyz.tfstate    # WordPress site states
│   └── ptoken-agency.tfstate
└── anythingllm/
    └── anythingllm.tfstate      # AI platform state
```

### Access Control

- **Bucket**: `weown-dev-backup`
- **Access Keys**: Per-project, limited to specific paths
- **Encryption**: SSE-C with 32-byte AES-256 keys

## Backup Security

### Encryption Model

- **Algorithm**: AES-256-GCM
- **Key Management**: PGP asymmetric encryption
- **Public Key**: Available to projects for encryption
- **Private Key**: Stored in Infisical, exec-only for executives

### Backup Naming Convention

```
weown-dev-backup/
├── backups/
│   ├── sso/
│   │   ├── sso_backup_20260426_120000.sql.gpg
│   │   └── sso_backup_20260426_120000.tar.gz.gpg
│   └── wordpress/
│       └── burnedout-xyz/
│           └── burnedout-xyz_backup_20260426_120000.sql.gpg
```

### Key Management

1. **Generation**: Executives generate PGP key pair
2. **Public Key**: Distributed to projects via Infisical
3. **Private Key**: Stored in Infisical with exec-only access
4. **Rotation**: Annual rotation recommended

## Access Control Matrix

| Role | Deploy | Monitor | Backup | Restore | Decrypt |
|------|--------|---------|--------|---------|---------|
| Developer | Yes | Yes | No | No | No |
| Operator | No | Yes | Yes | No | No |
| Executive | No | No | No | Yes | Yes |

## Implementation

### Terraform Backend

```hcl
backend "s3" {
  bucket         = "weown-dev-backup"
  key            = "sso/sso.tfstate"
  sse_customer_key = var.spaces_encryption_key
  # ...
}
```

### Backup Script

```bash
# Encrypt backup with PGP public key
gpg --encrypt --recipient "backup@weown.ai" \
    --output "backup.sql.gpg" \
    "backup.sql"
```

### Restore Script (Executive Only)

```bash
# Decrypt backup with PGP private key
gpg --decrypt \
    --output "backup.sql" \
    "backup.sql.gpg"
```

## Audit and Compliance

### Logging

- All state access logged
- Backup operations logged
- Key usage logged

### Monitoring

- Unusual access patterns detected
- Failed decryption attempts alerted
- Key rotation tracked

## Incident Response

### Key Compromise

1. Rotate compromised keys immediately
2. Re-encrypt all data with new keys
3. Audit access logs
4. Notify security team

### State Corruption

1. Restore from known-good backup
2. Verify state integrity
3. Investigate root cause
4. Update procedures

## References

- [DigitalOcean Spaces SSE-C](https://docs.digitalocean.com/reference/api/spaces-api/)
- [OpenTofu State Security](https://opentofu.org/docs/language/state/)
- [PGP Best Practices](https://riseup.net/en/security/message-security/openpgp/best-practices)
