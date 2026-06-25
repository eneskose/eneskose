# Changelog

All notable changes to this collection are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-24

### Added

- Initial release of the `rek.teleport` collection.
- `teleport_install` role: repository/tarball installation of Teleport
  Enterprise (`teleport-ent`), system user/directories, Enterprise license
  placement, systemd unit and environment file, shared restart/reload handlers.
- `teleport_auth` role: renders and manages the Auth Service `teleport.yaml`
  (cluster name, backend storage, provisioning tokens, authentication).
- `teleport_proxy` role: renders and manages the Proxy Service `teleport.yaml`
  including cluster-join configuration (auth server, CA pin, join token) and
  TLS via ACME or supplied key pairs.
- `teleport_cleanup` role: completely removes Teleport (service, unit, package,
  yum repo, tarball binaries, config, env file, data dir, license and managed
  user) to return a host to a clean state for a fresh install. Idempotent and
  safe to run on a host that never had Teleport.
- `teleport_status` role: read-only health/state verification (service state,
  version, `/readyz`, proxy web API ping, `tctl` cluster status and node count,
  version-drift summary). Reports by default; `teleport_status_assert=true`
  fails the play as a CI/post-deploy gate. Check-mode safe, depends on nothing.
- `teleport_resources` role: applies dynamic cluster resources via `tctl`
  (RBAC roles, SSO connectors github/saml/oidc, `cluster_auth_preference`,
  users) from complete resource documents, in dependency order, on the Auth
  node. Secrets applied with `no_log`; upsert-only (no pruning).
- Sample inventory, `group_vars`, and `site.yml` / `auth.yml` / `proxy.yml` /
  `cleanup.yml` / `status.yml` / `resources.yml` playbooks.
- Per-environment inventories (`hosts.yml`, `hw01.yml`, `dev02.yml`) with
  jump-host (SSH `ProxyJump`) bootstrap wiring; see `docs/bastion.md`.
- yamllint and ansible-lint (production profile) configuration.

### Notes

- Targets the RHEL OS family (EL 8/9) via the yum repository; other
  distributions can install via `teleport_install_method: tarball`.
- Single Auth instance uses the built-in SQLite backend by default.
