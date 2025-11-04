# Changelog

## [1.1.0] - 2025-11-03

### Fixed
- **Security Context**: Removed overly restrictive `runAsUser` and `runAsNonRoot` settings that caused permission denied errors during PHP configuration
- **Container Stability**: Fixed CrashLoopBackOff issue preventing Nextcloud container from starting

### Changed
- **Resource Allocation**: Restored production-recommended resource requests and limits:
  - Nextcloud app: 1Gi request / 2Gi limit
  - PostgreSQL: 512Mi request / 1Gi limit  
  - Redis: 64Mi request / 128Mi limit
  - Cron: 128Mi request / 256Mi limit

## [1.0.0] - 2024-01-10

### Added
- Initial Nextcloud deployment for Kubernetes
- PostgreSQL database backend
- Redis cache for sessions
- Interactive deployment script
- One-command installer

- Security features with NetworkPolicy and RBAC
- TLS certificates with Let's Encrypt
- Persistent storage and backups
- Health checks and monitoring
- Resource quotas and limits

