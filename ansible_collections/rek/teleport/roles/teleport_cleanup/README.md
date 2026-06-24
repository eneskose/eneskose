# Role: `rek.teleport.teleport_cleanup`

Completely removes Teleport from a host and returns it to a clean state, ready
for a fresh install + config. Idempotent and safe to run on a host that never
had Teleport (every step is guarded or `state: absent`).

It does **not** depend on `teleport_install`, so running it can never
re-provision anything.

## What it removes

1. Stops and disables the `teleport` systemd service.
2. Deletes the hardened unit `/etc/systemd/system/teleport.service`, reloads
   systemd and clears any failed state.
3. Uninstalls the `teleport` / `teleport-ent` package (`dnf` + autoremove).
4. Removes the Teleport **yum repository** definition.
5. Removes tarball-installed binaries from `/usr/local/bin` (`teleport`, `tctl`,
   `tsh`, `tbot`, `fdpass-teleport`, `teleport-update`).
6. Removes the config (`/etc/teleport.yaml`), environment file
   (`/etc/sysconfig/teleport`), PID file and any file-based log.
7. **Wipes the data directory** (`/var/lib/teleport`) and the Enterprise
   license — this clears cluster state and host certificates.
8. Removes the managed system user/group (only when `teleport_run_as_root: false`).

## ⚠️ Data loss

With `teleport_cleanup_remove_data: true` (the default) this **destroys cluster
state**: on an Auth node that means the backend (users, roles, CA) is gone; on
any node the host certificates are gone. That is exactly what you want before a
fresh build — but it is irreversible. Set `teleport_cleanup_remove_data: false`
to keep `/var/lib/teleport` (e.g. to reinstall the same binary while preserving
the cluster).

## Key variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `teleport_cleanup_remove_package` | `true` | dnf-remove the package |
| `teleport_cleanup_remove_repo` | `true` | remove the yum repo |
| `teleport_cleanup_remove_binaries` | `true` | remove `/usr/local/bin` binaries |
| `teleport_cleanup_remove_data` | `true` | wipe data dir + license |
| `teleport_cleanup_remove_user` | `true` | remove managed user/group |

Path/identity variables (`teleport_data_dir`, `teleport_config_path`,
`teleport_service_name`, …) share names with `teleport_install`, so any
customisation you set for the install is reused here automatically.

## Example

```yaml
- hosts: teleport_auth:teleport_proxy
  become: true
  roles:
    - role: rek.teleport.teleport_cleanup
```

Keep the data dir while removing the binary:

```yaml
- hosts: teleport_proxy
  become: true
  roles:
    - role: rek.teleport.teleport_cleanup
      vars:
        teleport_cleanup_remove_data: false
```
