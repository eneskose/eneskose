# Architecture & role design

## Why this role split

Teleport runs as a single binary driven by one `teleport.yaml`, but a
production cluster separates concerns across instances. The Auth Service is the
certificate authority and source of truth and must stay on a private network;
the Proxy Service is the public front door. Because each VM is single-purpose,
each renders its own focused `teleport.yaml`.

The collection mirrors that separation while keeping installation logic in one
place:

```
                 ┌────────────────────────┐
                 │     teleport_install     │  base role (no service config)
                 │  pkg/tarball · user ·    │  ← dependency of both below
                 │  license · systemd ·     │
                 │  handlers                │
                 └───────────┬──────────────┘
            depends on       │        depends on
        ┌────────────────────┴───────────────────┐
        ▼                                         ▼
┌────────────────┐                       ┌────────────────┐
│  teleport_auth  │                       │ teleport_proxy │
│  auth_service:  │  3025 (private)       │ proxy_service: │  443 (public)
│  enabled        │ ◄──────────────────── │ joins cluster  │
└────────────────┘   join token + CA pin  └────────────────┘
```

- **`teleport_install`** owns everything identical across node types:
  install, system user, data dir, Enterprise license, the hardened systemd
  unit, and the shared `Restart/Reload Teleport` handlers. It does **not**
  render `teleport.yaml` or start the daemon.
- **`teleport_auth`** and **`teleport_proxy`** each `depends on`
  `teleport_install` (via `meta/main.yml`), render their node's complete
  `teleport.yaml`, validate it with `teleport configtest`, and start the
  service — notifying the inherited restart handler on change.

This keeps install logic DRY and the two service roles independently usable and
single-responsibility. Single-purpose nodes are assumed; running Auth and Proxy
on the same host would require a combined config and is out of scope.

## How the Proxy joins the Auth Service

1. Bring up the Auth Service (`teleport_auth`).
2. On the Auth host, mint a join token and read the CA pin:
   ```bash
   tctl tokens add --type=proxy,node --ttl=1h
   tctl status        # copy the "CA pin: sha256:..." value
   ```
3. Feed `teleport_join_token`, `teleport_ca_pin`, and `teleport_auth_server`
   into the Proxy role and run `teleport_proxy`.

Static tokens (`teleport_auth_tokens`) are supported for bootstrapping but
short-lived dynamic tokens or platform join methods (IAM, Kubernetes) are
preferred in production.

## Network ports

| Port | Service | Exposure | Purpose |
| --- | --- | --- | --- |
| 3025 | Auth | private | Auth API (Proxy/Nodes connect here) |
| 443  | Proxy | public | Web UI + TLS routing (SSH/Kube/DB multiplexed) |
| 3023 | Proxy | public | SSH proxy (when TLS routing is off) |
| 3024 | Proxy | public | Reverse tunnel for trusted clusters / agents |
| 3080 | Proxy | public | Legacy web UI port (older configs) |
| 3026 | Proxy | public | Kubernetes proxy (when not multiplexed) |
| 3000 | both | private | Optional diagnostics/metrics (`teleport_diag_addr`) |

With `proxy_listener_mode: multiplex` (the default here), clients use **443**
for everything and the other proxy ports are not required.

## Backend storage

A single Auth instance uses the built-in SQLite backend under `data_dir` — no
extra setup. For high availability, run multiple Auth instances behind a load
balancer with a shared external backend (etcd, DynamoDB, Firestore) via
`teleport_auth_storage`.
