# harbor-registry

> #WeOwnVer: v5.1.3.1

## [Unreleased]

### Added

- Self-contained Harbor v2.15.4 registry for `registry.weown.tools` on a new ATL1 v5 Shared droplet (`s5-2vcpu-4gb-80gb`, Ubuntu 24.04). Caddy 2.11.7 terminates TLS. Named Docker volumes hold the database, registry blobs, and jobservice logs. Public DNS is the Cloudflare A record (grey cloud). The We Own Labs DigitalOcean zone is not delegated. No existing compose file, workflow, or droplet is modified.
