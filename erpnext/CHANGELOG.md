# ERPNext review artifacts

## [Unreleased]

### Added

- Helm values for `erp.weown.tools` require `weown.dev/pool=erpnext`. Upstream MariaDB 8.0.89 ignores affinity, so `scripts/pin-pool.py` inserts it before install. `scripts/install.sh` dry-runs that check and reads `ERP_DB_ROOT_PASSWORD` from the environment.
- `jobs.volumePermissions` is a one-shot chown of the sites PVC. Leave it disabled after it completes; the chart stamps a new Job name on every render. `jobs.configure` writes `sites/apps.txt` and the Valkey endpoints. `scripts/new-site-job.yaml` creates the site without putting the admin password in the chart values or the job log.
