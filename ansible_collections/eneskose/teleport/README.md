# Ansible Collection — `eneskose.teleport`

Deploy and manage **self-hosted Teleport Enterprise (PAM)** clusters on Linux
VMs. The collection provides composable roles for the **Auth Service** and the
**Proxy Service** running on dedicated instances.

> Teleport Enterprise is the commercial edition and requires a license file.
> Set `teleport_edition: oss` to deploy the open-source edition instead.

## Roles

| Role | Responsibility |
| --- | --- |
| [`teleport_install`](roles/teleport_install/README.md) | Base layer: install `teleport-ent` (repo or tarball), system user, data dir, Enterprise license, hardened systemd unit, shared handlers. |
| [`teleport_auth`](roles/teleport_auth/README.md) | Render & run the **Auth Service** (cluster CA, backend, tokens, MFA). Private network. |
| [`teleport_proxy`](roles/teleport_proxy/README.md) | Render & run the **Proxy Service** joined to Auth (CA pin + token, TLS/ACME). Internet-facing. |

The two service roles depend on `teleport_install`, so applying a service role
pulls the base role in automatically. See
[`docs/architecture.md`](docs/architecture.md) for the design rationale, the
Auth↔Proxy join flow, and the network-port reference.

## Requirements

- Ansible `>=2.15` (`ansible-core`) on the controller.
- Target VMs: Ubuntu/Debian or RHEL-family (EL 8/9). `become: true`.
- A Teleport **Enterprise license** (`license.pem`) for the default edition.

## Install

```bash
# From a local checkout of this repo:
ansible-galaxy collection install ./ansible_collections/eneskose/teleport

# Or build & install a tarball:
ansible-galaxy collection build ansible_collections/eneskose/teleport
ansible-galaxy collection install eneskose-teleport-1.0.0.tar.gz
```

## Quick start

1. Edit the sample inventory and group vars under
   [`playbooks/inventory/`](playbooks/inventory/).
2. Vault-encrypt your secrets (license, join token):
   ```bash
   ansible-vault encrypt_string 'proxy,node:<token>' --name vault_teleport_join_token
   ```
3. Deploy the whole cluster (Auth first, then Proxy):
   ```bash
   ansible-playbook -i playbooks/inventory/hosts.yml \
     playbooks/site.yml --ask-vault-pass
   ```
4. After Auth is up, mint the proxy join token and read the CA pin on the Auth
   host, then deploy the proxy:
   ```bash
   tctl tokens add --type=proxy,node --ttl=1h
   tctl status                      # copy the CA pin
   ansible-playbook -i playbooks/inventory/hosts.yml \
     playbooks/proxy.yml --ask-vault-pass
   ```

### Minimal playbook

```yaml
- hosts: teleport_auth
  become: true
  roles:
    - role: eneskose.teleport.teleport_auth
      vars:
        teleport_license_src: "files/license.pem"   # vaulted
        teleport_auth_cluster_name: "teleport.example.com"

- hosts: teleport_proxy
  become: true
  roles:
    - role: eneskose.teleport.teleport_proxy
      vars:
        teleport_license_src: "files/license.pem"
        teleport_auth_server: "10.0.1.10:3025"
        teleport_ca_pin: ["sha256:...."]
        teleport_join_token: "{{ vault_teleport_join_token }}"
        teleport_proxy_public_addr: "teleport.example.com:443"
        teleport_proxy_acme_enabled: true
        teleport_proxy_acme_email: "ops@example.com"
```

## Security notes

- **Never commit unencrypted secrets.** Encrypt the license and join tokens
  with Ansible Vault. License/token tasks use `no_log`.
- The Auth Service should be on a **private** network only (port 3025). The
  Proxy is the only internet-facing component.
- Prefer **WebAuthn** MFA (`teleport_auth_second_factor: webauthn`) and
  short-lived/dynamic join tokens over static tokens.
- Always set `teleport_ca_pin` so proxies/nodes verify the cluster on join.
- Review `teleport_repo_channel` to match the Teleport major version you intend
  to run.

## Development & testing

```bash
yamllint .
ansible-lint
molecule test            # requires Docker; installs OSS edition for the smoke test
```

CI (lint, syntax-check, collection build) runs via
[`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## License

Apache-2.0. See [LICENSE](LICENSE).
