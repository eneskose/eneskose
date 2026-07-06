# Role: `rek.teleport.teleport_proxy`

Configures and runs the **Teleport Proxy Service** on a dedicated,
internet-facing instance, joined to an existing Auth Service. The Proxy is the
front door of the cluster and is the only component that should be reachable
from the public internet.

Depends on `teleport_install`, which runs automatically.

## What it does

1. Validates the Proxy-specific variables.
2. **Auto-bootstraps the join** (`teleport_proxy_autojoin`, default true): when
   `teleport_ca_pin` / `teleport_join_token` are empty, it includes the shared
   [`teleport_join`](../teleport_join/README.md) role (token type `proxy,node`),
   which delegates to an Auth host to read the CA pin (`tctl status`) and mint
   a short-lived join token (`tctl tokens add`) — no manual copy/paste. Waits
   (retries) for the Auth Service to be reachable.
3. Obtains the serving certificate (`teleport_proxy_tls_provider`): either you
   supply `teleport_proxy_https_keypairs`, or with `openbao` the Proxy issues
   one from OpenBao/Vault PKI — optionally **creating/updating the PKI role
   first** (`teleport_proxy_openbao_manage_role`) — see below.
4. Renders `/etc/teleport.yaml` with `proxy_service` enabled (and `auth`/`ssh`
   disabled) plus the cluster-join settings — validated with
   `teleport configure --test`.
5. Enables and starts the `teleport` systemd service.

## TLS certificate

| `teleport_proxy_tls_provider` | Behaviour |
| --- | --- |
| `keypairs` (default) | Use the cert/key in `teleport_proxy_https_keypairs` (none → Teleport self-signs) |
| `openbao` | Issue from OpenBao/Vault PKI on the Proxy host at run time |

With `openbao`, the Proxy runs `community.hashi_vault.vault_pki_generate_certificate`
locally (so the private key never leaves the Proxy), writes the key (`0600`) and
cert (leaf + chain) under `teleport_proxy_tls_dir`, and points `https_keypairs`
at them. It **re-issues only when the cert is missing or within
`teleport_proxy_openbao_renew_threshold_days` of expiry** (checked with
`openssl x509 -checkend`), so repeated runs don't churn. Requirements: the
`community.hashi_vault` collection where Ansible runs, the `hvac` Python library
on the Proxy (installed by the role), and network access to OpenBao.

### Managing the PKI role (optional)

Set `teleport_proxy_openbao_manage_role: true` to have the run **create/update
the PKI role it issues from, just before issuing** (via
`community.hashi_vault.vault_write` to `<pki_mount>/roles/<pki_role>`), so the
role policy always matches the cert request. The policy is driven by
`teleport_proxy_openbao_pki_allowed_domains` (defaults to the cert common name
plus its DNS SANs),
`teleport_proxy_openbao_pki_allow_{subdomains,bare_domains,wildcard_certificates}`,
the `server_flag`/`client_flag` EKUs, and `teleport_proxy_openbao_pki_max_ttl`.
It runs only when a (re)issue is needed, so converged runs stay quiet. **Token
note:** this needs an OpenBao token with write access to the role path — broader
than the issue-only capability the certificate step requires; leave the toggle
off if the PKI admin provisions the role out-of-band.

## Auto-join vs explicit

| | Behaviour |
| --- | --- |
| `teleport_proxy_autojoin: true` (default), pin/token empty | Discovered + minted on the Auth host at run time |
| `teleport_ca_pin` / `teleport_join_token` set | Used as-is (auto-join skipped for that value) |
| `teleport_proxy_autojoin: false` | Nothing auto-discovered; supply values yourself |

Auto-join needs an Auth host in the inventory (`teleport_autojoin_auth_host`,
default the first `teleport_auth` member), reachable at run time, with the Auth
Service up. **Trust note:** the CA pin is fetched over your Ansible→Auth SSH
channel rather than an independent out-of-band path — fine in the usual model,
but set `teleport_ca_pin` explicitly if you need true out-of-band pinning.

## Key variables

See [`defaults/main.yml`](defaults/main.yml). Highlights:

| Variable | Default | Purpose |
| --- | --- | --- |
| `teleport_auth_server` | `auth.example.com:3025` | Auth API address (private network) |
| `teleport_proxy_autojoin` | `true` | Discover CA pin + mint token from the Auth host |
| `teleport_join_token_ttl` | `1h` | TTL for the auto-minted token |
| `teleport_ca_pin` | `[]` | Set to pin out-of-band (else auto-discovered) |
| `teleport_join_token` | `""` | Set to use a static token (else auto-minted) |
| `teleport_proxy_public_addr` | `teleport.example.com:443` | Public entrypoint |
| `teleport_proxy_tls_provider` | `keypairs` | `keypairs` or `openbao` |
| `teleport_proxy_https_keypairs` | `[]` | Bring-your-own TLS certs |
| `teleport_proxy_openbao_url` | `""` | OpenBao API address (openbao provider) |
| `teleport_proxy_openbao_pki_role` | `teleport-proxy` | PKI role to issue from |

## Example (auto-join + OpenBao PKI)

```yaml
- hosts: teleport_proxy
  become: true
  roles:
    - role: rek.teleport.teleport_proxy
      vars:
        teleport_auth_server: "10.0.1.10:3025"
        teleport_proxy_public_addr: "teleport.example.com:443"
        # CA pin + join token discovered/minted from the Auth host automatically
        teleport_proxy_tls_provider: openbao
        teleport_proxy_openbao_url: "https://openbao.example.com:8200"
        teleport_proxy_openbao_token: "{{ vault_openbao_token }}"
        teleport_proxy_openbao_pki_role: teleport-proxy
```
