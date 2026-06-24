# Role: `eneskose.teleport.teleport_proxy`

Configures and runs the **Teleport Proxy Service** on a dedicated,
internet-facing instance, joined to an existing Auth Service. The Proxy is the
front door of the cluster and is the only component that should be reachable
from the public internet.

Depends on `teleport_install`, which runs automatically.

## What it does

1. Validates the Proxy-specific variables (and warns when joining without a CA
   pin).
2. Renders `/etc/teleport.yaml` with `proxy_service` enabled (and `auth`/`ssh`
   disabled) plus the cluster-join settings — validated with
   `teleport configtest`.
3. Enables and starts the `teleport` systemd service.

## Key variables

See [`defaults/main.yml`](defaults/main.yml). Highlights:

| Variable | Default | Purpose |
| --- | --- | --- |
| `teleport_auth_server` | `auth.example.com:3025` | Auth API address (private network) |
| `teleport_ca_pin` | `[]` | CA pin(s) from `tctl status` (strongly recommended) |
| `teleport_join_token` | `""` | Join token from `tctl tokens add` (vault it) |
| `teleport_proxy_public_addr` | `teleport.example.com:443` | Public entrypoint |
| `teleport_proxy_acme_enabled` | `false` | Auto TLS via Let's Encrypt |
| `teleport_proxy_https_keypairs` | `[]` | Bring-your-own TLS certs |

## Example

```yaml
- hosts: teleport_proxy
  become: true
  roles:
    - role: eneskose.teleport.teleport_proxy
      vars:
        teleport_auth_server: "10.0.1.10:3025"
        teleport_ca_pin:
          - "sha256:1234abcd...."
        teleport_join_token: "{{ vault_teleport_join_token }}"
        teleport_proxy_public_addr: "teleport.example.com:443"
        teleport_proxy_acme_enabled: true
        teleport_proxy_acme_email: "ops@example.com"
```
