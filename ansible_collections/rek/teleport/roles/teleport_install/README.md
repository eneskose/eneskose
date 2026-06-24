# Role: `rek.teleport.teleport_install`

Base role that installs Teleport and provisions everything common to every
node type. It is a dependency of both `teleport_auth` and `teleport_proxy`, so
you normally don't run it directly — applying a service role pulls it in.

## What it does

1. Installs Teleport **Enterprise** (`teleport-ent`) or **OSS** (`teleport`)
   from the yum repository (RHEL family) or from the official CDN tarball.
2. Optionally creates a dedicated system user/group (when not running as root).
3. Creates the data directory (`/var/lib/teleport`, mode `0700`).
4. Installs the Enterprise **license** (`/var/lib/teleport/license.pem`).
5. Writes a hardened **systemd unit** and (optionally) the
   `/etc/sysconfig/teleport` environment file.
6. Defines the shared **handlers** (`Restart Teleport`, `Reload Teleport`,
   `Reload systemd`) that the service roles notify.

It deliberately does **not** render `teleport.yaml` or start the service — that
is owned by the `teleport_auth` / `teleport_proxy` roles, which write the
node's config and then start the daemon.

## Key variables

See [`defaults/main.yml`](defaults/main.yml) and
[`meta/argument_specs.yml`](meta/argument_specs.yml). Most important:

| Variable | Default | Purpose |
| --- | --- | --- |
| `teleport_edition` | `enterprise` | `enterprise` → `teleport-ent`, `oss` → `teleport` |
| `teleport_install_method` | `repository` | `repository` or `tarball` |
| `teleport_repo_channel` | `stable/v17` | **Review** for your target major |
| `teleport_version` | `""` | Required for tarball; optional repo pin |
| `teleport_license_src` / `teleport_license_content` | `""` | Enterprise license (vault these) |
| `teleport_run_as_root` | `true` | Upstream default; set `false` for an unprivileged user |

## Example

```yaml
- hosts: teleport_nodes
  become: true
  roles:
    - role: rek.teleport.teleport_install
      vars:
        teleport_edition: enterprise
        teleport_repo_channel: stable/v17
        teleport_license_src: "files/license.pem"   # vault-encrypted in real use
```
