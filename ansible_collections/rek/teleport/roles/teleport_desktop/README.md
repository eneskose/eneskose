# Role: `rek.teleport.teleport_desktop`

Configures and runs the **Teleport Windows Desktop Service** on a dedicated
**Linux** instance, joined to an existing Auth Service. The Desktop Service is
the RDP gateway of the cluster: it sits on the private network, registers
Windows hosts as `WindowsDesktop` resources, and proxies RDP sessions for
users coming in through the Proxy web UI. Only the Proxy connects to it
(port 3028 by convention) — it must not be internet-facing.

Depends on `teleport_install`, which runs automatically.

## What it does

1. Validates the Desktop-specific variables (and that at least one source of
   Windows hosts is configured: static hosts or Active Directory).
2. **Auto-bootstraps the join** (`teleport_desktop_autojoin`, default true):
   when `teleport_ca_pin` / `teleport_join_token` are empty, it includes the
   shared [`teleport_join`](../teleport_join/README.md) role (token type
   `windowsdesktop`), which delegates to an Auth host to read the CA pin and
   mint a short-lived join token.
3. Renders `/etc/teleport.yaml` with `windows_desktop_service` enabled (and
   `auth`/`proxy`/`ssh` disabled) — validated with `teleport configure --test`.
4. Enables and starts the `teleport` systemd service.

## Windows hosts: two registration modes

| Mode | How |
| --- | --- |
| **Non-AD (local users)** | List hosts in `teleport_desktop_static_hosts` with `ad: false`; users log in with local Windows accounts. |
| **Active Directory** | Set the `teleport_desktop_ldap_*` variables (LDAPS address, domain, service account + SID); optionally enable auto-discovery with `teleport_desktop_discovery_base_dn`. |

Both can be combined. Discovery requires the AD/LDAP connection.

```yaml
teleport_desktop_static_hosts:
  - name: win-build-01
    ad: false
    addr: 10.20.1.40:3389
    labels:
      env: hw01
```

## Manual Windows-side preparation (out of scope for this role)

This collection targets Linux VMs; each **Windows host** must be prepared
out-of-band before it is accessible:

1. **Import the Teleport user CA** on the Windows host:
   `curl.exe -fo teleport.cer https://<proxy_public_addr>/webapi/auth/export?type=windows`
2. **Run the Teleport Windows Auth Setup** executable (installs the smart-card
   auth DLL and, for local-user mode, disables Network Level Authentication).
3. For AD mode, follow Teleport's Active Directory guide instead (GPO-based
   CA + certificate deployment).

## RBAC

Users need a Teleport role allowing desktop access, e.g. `windows_desktop_labels`
plus `windows_desktop_logins` (the Windows account names). Deploy it with the
existing [`teleport_resources`](../teleport_resources/README.md) role:

```yaml
teleport_roles:
  - kind: role
    version: v7
    metadata:
      name: windows-desktop-access
    spec:
      allow:
        windows_desktop_labels:
          "env": ["hw01"]
        windows_desktop_logins: ["Administrator", "{{ '{{internal.windows_logins}}' }}"]
```

## Key variables

See [`defaults/main.yml`](defaults/main.yml). Highlights:

| Variable | Default | Purpose |
| --- | --- | --- |
| `teleport_auth_server` | `auth.example.com:3025` | Auth API address (private network) |
| `teleport_desktop_autojoin` | `true` | Discover CA pin + mint `windowsdesktop` token from the Auth host |
| `teleport_desktop_listen_addr` | `0.0.0.0:3028` | Service listen address (Proxy-facing) |
| `teleport_desktop_static_hosts` | `[]` | Non-AD Windows hosts to register |
| `teleport_desktop_ldap_addr` | `""` | Set to enable Active Directory integration |
| `teleport_desktop_discovery_base_dn` | `""` | LDAP auto-discovery (`'*'` = whole domain) |
| `teleport_desktop_host_labels` | `[]` | Regex → label rules for Windows hosts |
| `teleport_desktop_extra_config` | `{}` | Extra `windows_desktop_service` keys |

## Example (non-AD static hosts)

```yaml
- hosts: teleport_desktop
  become: true
  roles:
    - role: rek.teleport.teleport_desktop
      vars:
        teleport_auth_server: "10.20.1.10:3025"
        teleport_desktop_static_hosts:
          - name: win-build-01
            ad: false
            addr: 10.20.1.40
            labels:
              env: hw01
```
