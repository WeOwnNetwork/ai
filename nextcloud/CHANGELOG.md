# Changelog

## [1.1.0] - 2025-11-04

### Fixed
- **Security Context**: Removed overly restrictive `runAsUser` and `runAsNonRoot` settings that caused permission denied errors during PHP configuration
- **Container Stability**: Fixed CrashLoopBackOff issue preventing Nextcloud container from starting
- **Scheduling Issues**: Fixed pod stuck in Pending state due to node size constraints (autoscaler couldn't add nodes large enough for original 500m CPU request)

### Changed
- **Resource Allocation**: Balanced configuration based on Nextcloud official docs (512MB recommended) and small cluster reality:
  - Nextcloud app: 200m CPU / 512Mi memory (meets official minimum 512MB recommendation)
  - PostgreSQL: 150m CPU / 384Mi memory (sufficient for small-medium deployments)
  - Redis: 50m CPU / 64Mi memory (unchanged)
  - Cron: 25m CPU / 64Mi memory (minimal for periodic tasks)
  - **Total**: 425m CPU / 1,024Mi memory (fits on node types with ~1GB+ available)

### Notes
- **Autoscaler Behavior**: Cluster autoscaler will only add nodes if the pod can fit on that node type
- **Node Size Matters**: Small node types (~1 vCPU) cannot accommodate large CPU requests even when empty
- **Production Recommendation**: For full production workloads, consider larger node types (2+ vCPU) or reduce resource requests further

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

