# Role: `rek.teleport.teleport_join`

**Internal helper role** — auto-bootstraps an agent's cluster join. It is
included by the service roles (`teleport_proxy`, `teleport_desktop`) and is not
usually applied directly.

## What it does

Delegates to an Auth host (`teleport_autojoin_auth_host`, default the first
`teleport_auth` member) to:

1. **Discover the CA pin** — runs `tctl status` and extracts the `sha256:...`
   pin(s). Skipped when `teleport_ca_pin` is already set.
2. **Mint a short-lived join token** — runs
   `tctl tokens add --type=<teleport_join_token_type> --ttl=<teleport_join_token_ttl>`.
   Skipped when `teleport_join_token` is already set.

Both steps retry while waiting for the Auth Service to become reachable, run
once per play (`run_once`), and set the `teleport_ca_pin` /
`teleport_join_token` facts for the calling role to render into its config.

## Usage (from a service role)

```yaml
- name: Auto-discover CA pin and mint join token from the Auth host
  ansible.builtin.include_role:
    name: rek.teleport.teleport_join
  vars:
    teleport_join_token_type: "windowsdesktop"   # token type for this agent
  when:
    - my_role_autojoin | bool
    - (teleport_ca_pin | length == 0) or (teleport_join_token | length == 0)
```

## Key variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `teleport_join_token_type` | `proxy,node` | System role(s) in the minted token |
| `teleport_join_token_ttl` | `1h` | TTL for the minted token |
| `teleport_autojoin_auth_host` | first `teleport_auth` host | Delegation target |
| `teleport_tctl_bin` | `<teleport_bin dir>/tctl` | tctl path on the Auth host |

**Trust note:** the CA pin is fetched over your Ansible→Auth SSH channel rather
than an independent out-of-band path — fine in the usual model, but set
`teleport_ca_pin` explicitly if you need true out-of-band pinning.
