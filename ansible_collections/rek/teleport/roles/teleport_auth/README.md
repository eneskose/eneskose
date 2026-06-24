# Role: `rek.teleport.teleport_auth`

Configures and runs the **Teleport Auth Service** on a dedicated instance. The
Auth Service is the cluster's certificate authority and source of truth; it
should run on a private network and never be exposed to the internet.

Depends on `teleport_install` (installs the binary, license, systemd unit and
handlers), which runs automatically.

## What it does

1. Validates the Auth-specific variables.
2. Renders `/etc/teleport.yaml` with `auth_service` enabled (and `proxy`/`ssh`
   disabled) — validated with `teleport configtest` before being applied.
3. Enables and starts the `teleport` systemd service.

## Key variables

See [`defaults/main.yml`](defaults/main.yml). Highlights:

| Variable | Default | Purpose |
| --- | --- | --- |
| `teleport_auth_cluster_name` | `teleport.example.com` | **Permanent** cluster name |
| `teleport_auth_listen_addr` | `0.0.0.0:3025` | Auth API listen address (keep private) |
| `teleport_auth_second_factor` | `otp` | MFA policy (`webauthn` recommended) |
| `teleport_auth_tokens` | `[]` | Static join tokens (vault them; prefer dynamic) |
| `teleport_auth_storage` | `{}` | External backend for HA (etcd/DynamoDB/...) |

## Example

```yaml
- hosts: teleport_auth
  become: true
  roles:
    - role: rek.teleport.teleport_auth
      vars:
        teleport_auth_cluster_name: "teleport.example.com"
        teleport_auth_second_factor: "webauthn"
        teleport_auth_webauthn_rp_id: "teleport.example.com"
        teleport_auth_tokens:
          - "proxy,node:{{ vault_teleport_join_token }}"
```

## Generating a join token & CA pin for proxies/nodes

After the Auth Service is up, create short-lived tokens and read the CA pin on
the Auth host:

```bash
# Create a token that lets Proxy and Node services join:
tctl tokens add --type=proxy,node --ttl=1h

# Print the CA pin the joining nodes should verify:
tctl status   # shows the "CA pin: sha256:..." value
```

Feed those into `teleport_join_token` and `teleport_ca_pin` for the proxy role.
