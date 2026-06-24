# Changelog

All notable changes to this collection are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-24

### Added

- Initial release of the `eneskose.teleport` collection.
- `teleport_install` role: repository/tarball installation of Teleport
  Enterprise (`teleport-ent`), system user/directories, Enterprise license
  placement, systemd unit and environment file, shared restart/reload handlers.
- `teleport_auth` role: renders and manages the Auth Service `teleport.yaml`
  (cluster name, backend storage, provisioning tokens, authentication).
- `teleport_proxy` role: renders and manages the Proxy Service `teleport.yaml`
  including cluster-join configuration (auth server, CA pin, join token) and
  TLS via ACME or supplied key pairs.
- Sample inventory, `group_vars`, and `site.yml` / `auth.yml` / `proxy.yml`
  playbooks.
- yamllint and ansible-lint (production profile) configuration.

### Notes

- Targets the RHEL OS family (EL 8/9) via the yum repository; other
  distributions can install via `teleport_install_method: tarball`.
- Single Auth instance uses the built-in SQLite backend by default.
