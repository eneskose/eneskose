# Role: `rek.teleport.teleport_status`

Read-only verification of Teleport node and cluster health. It makes **no
changes** (every task is `changed_when: false` and runs even under `--check`)
and depends on nothing. By default it **reports**; set
`teleport_status_assert: true` to fail the play on any unhealthy result — useful
as a post-deploy smoke test or CI gate.

> Scope: this is point-in-time *verification*, not continuous monitoring. For
> ongoing health, use Teleport's Prometheus metrics on the diagnostic address,
> `tctl inventory status`, or the web UI. This role complements those.

## Checks

| Check | Method | Runs on |
|-------|--------|---------|
| Service active / enabled | `service_facts` | every node |
| Version | `teleport version` | every node |
| Readiness | `GET http://127.0.0.1:<diag_port>/readyz` | every node *(if `teleport_diag_addr` set)* |
| Proxy web API | `GET https://<public_addr>/webapi/ping` | proxy nodes |
| Cluster status | `tctl status` | auth nodes (local admin socket) |
| Joined node count | `tctl nodes ls --format=json` | auth nodes |
| Version drift | compares versions across the fleet | summary |

Each host gets a `teleport_status` fact (and the fleet is printed once):

```yaml
teleport_status:
  host: auth1.hw01.example.com
  roles: teleport_auth
  version: v17.0.4
  service_active: ok        # ok | fail
  service_enabled: ok       # ok | fail
  readyz: ok                # ok | fail | skipped
  proxy_ping: n/a           # ok | fail | skipped | n/a
  cluster: ok               # ok | fail | skipped | n/a
  nodes: 7                  # count | fail | n/a
```

`assert` mode fails when any of `service_active`, `readyz`, `proxy_ping` or
`cluster` is `fail` (values of `skipped`/`n/a` never fail).

## Requirements

- **Privilege** for the cluster checks: `tctl status` uses the local admin
  socket on the auth node, so run with `become: true` (the bundled
  `playbooks/status.yml` does).
- **Readiness probe** needs `teleport_diag_addr` set (it's empty by default).
  Enable it on the nodes to get `/readyz`; otherwise that check reports
  `skipped`.

## Usage

```bash
# Report (non-failing)
ansible-playbook -i playbooks/inventory/hw01.yml playbooks/status.yml

# Strict gate — fail on any unhealthy result
ansible-playbook -i playbooks/inventory/hw01.yml playbooks/status.yml \
  -e teleport_status_assert=true
```

As a post-deploy check, run it right after `site.yml`. During bootstrap (before
the proxy has a trusted certificate) you may want
`-e teleport_status_verify_tls=false` or `-e teleport_status_check_proxy_ping=false`.
