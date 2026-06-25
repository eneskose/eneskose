# Ansible Collection — `rek.teleport`

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
| [`teleport_cleanup`](roles/teleport_cleanup/README.md) | Completely remove Teleport (service, package, repo, binaries, config, data, user) and return the host to a clean state for a fresh install. |
| [`teleport_status`](roles/teleport_status/README.md) | Read-only health/state verification (service, version, `/readyz`, proxy ping, `tctl` cluster status, version drift). Reports by default; can assert as a CI/post-deploy gate. |
| [`teleport_resources`](roles/teleport_resources/README.md) | Apply dynamic cluster resources via `tctl` — RBAC roles, SSO connectors (github/saml/oidc), `cluster_auth_preference`, users. Runs on the Auth node. |

The two service roles depend on `teleport_install`, so applying a service role
pulls the base role in automatically. `teleport_cleanup`, `teleport_status` and
`teleport_resources` are standalone and depend on nothing. See
[`docs/architecture.md`](docs/architecture.md) for the design rationale, the
Auth↔Proxy join flow, and the network-port reference.

## Requirements

- Ansible `>=2.15` (`ansible-core`) on the controller.
- Target VMs: **RHEL family** — RHEL / CentOS / Rocky / Alma / Amazon Linux
  (EL 8/9). `become: true`. (Other distros can use
  `teleport_install_method: tarball`.)
- A Teleport **Enterprise license** (`license.pem`) for the default edition.

## Install

```bash
# From a local checkout of this repo:
ansible-galaxy collection install ./ansible_collections/rek/teleport

# Or build & install a tarball:
ansible-galaxy collection build ansible_collections/rek/teleport
ansible-galaxy collection install rek-teleport-1.0.0.tar.gz
```

To run the roles inside a container with `ansible-navigator` or Ansible
Automation Platform / Automation Controller, use the bundled execution
environment under [`execution-environment/`](../../../execution-environment/).

## Quick start

1. Edit the sample inventory and group vars under
   [`playbooks/inventory/`](playbooks/inventory/). Each environment has its own
   inventory file — `hosts.yml` (example), `hw01.yml`, `dev02.yml` — plus a
   matching `group_vars/<env>.yml` for environment-specific values (cluster
   name, public address, Auth server). Shared role defaults stay in
   `group_vars/teleport_auth.yml` / `teleport_proxy.yml`; pick an environment
   by pointing `-i` at its file.
2. Vault-encrypt your Enterprise license (and any other secrets); see the
   security notes below.
3. Deploy the whole cluster — Auth first, then Proxy, in one run:
   ```bash
   ansible-playbook -i playbooks/inventory/hosts.yml \
     playbooks/site.yml --ask-vault-pass
   ```
   The Proxy **auto-bootstraps its join**: it reads the CA pin and mints a
   short-lived join token from the Auth host (`teleport_proxy_autojoin`, default
   on), so there's no manual `tctl status` / `tctl tokens add` step. To opt out,
   set `teleport_ca_pin` / `teleport_join_token` explicitly.

### Hosts behind a jump host

When the nodes aren't reachable directly, connections are proxied through a
bastion using SSH `ProxyJump`, configured per environment in
`group_vars/<env>.yml` (`teleport_bastion` + `ansible_ssh_common_args`). No
`~/.ssh/config` needed. See [`docs/bastion.md`](docs/bastion.md) for host-key
handling, auth options, and AAP/EE notes.

### Configure SSO, roles and other resources

Cluster resources (RBAC roles, SSO connectors, default auth preference) are
*dynamic* — not part of `teleport.yaml`. Define them as (vaulted) variables and
apply them on the Auth node:

```bash
ansible-playbook -i playbooks/inventory/hosts.yml playbooks/resources.yml --ask-vault-pass
```

See the [`teleport_resources`](roles/teleport_resources/README.md) role for the
variable shapes and a GitHub-SSO example.

### Verify cluster health

```bash
ansible-playbook -i playbooks/inventory/hosts.yml playbooks/status.yml
```

Read-only; prints a per-node + fleet summary. Add `-e teleport_status_assert=true`
to fail on any unhealthy result (CI/post-deploy gate). See the
[`teleport_status`](roles/teleport_status/README.md) role.

### Cleanup / fresh start

Remove Teleport from every node and return them to a clean state:

```bash
ansible-playbook -i playbooks/inventory/hosts.yml playbooks/cleanup.yml
```

⚠️ Defaults wipe `/var/lib/teleport` (cluster state, certs, license). Pass
`-e teleport_cleanup_remove_data=false` to keep the data directory. See the
[`teleport_cleanup`](roles/teleport_cleanup/README.md) role.

### Minimal playbook

```yaml
- hosts: teleport_auth
  become: true
  roles:
    - role: rek.teleport.teleport_auth
      vars:
        teleport_license_src: "files/license.pem"   # vaulted
        teleport_auth_cluster_name: "teleport.example.com"

- hosts: teleport_proxy
  become: true
  roles:
    - role: rek.teleport.teleport_proxy
      vars:
        teleport_license_src: "files/license.pem"
        teleport_auth_server: "10.0.1.10:3025"
        # CA pin + join token auto-bootstrapped from the Auth host
        # (teleport_proxy_autojoin); set them here only to opt out.
        teleport_proxy_public_addr: "teleport.example.com:443"
        teleport_proxy_acme_enabled: true
        teleport_proxy_acme_email: "ops@example.com"
```

## Security notes

- **Never commit unencrypted secrets.** Encrypt the license and join tokens
  with Ansible Vault. License/token tasks use `no_log`.
- The Auth Service should be on a **private** network only (port 3025). The
  Proxy is the only internet-facing component.
- Prefer **WebAuthn** MFA (`teleport_auth_second_factor: webauthn`). The Proxy
  uses **short-lived, auto-minted** join tokens by default (`teleport_proxy_autojoin`)
  rather than long-lived static ones.
- The Proxy verifies the cluster on join via the **CA pin**, auto-discovered
  from the Auth host (or set `teleport_ca_pin` to pin it out-of-band). Note that
  auto-discovery anchors trust on your Ansible→Auth SSH channel — see
  [`roles/teleport_proxy`](roles/teleport_proxy/README.md).
- Review `teleport_repo_channel` to match the Teleport major version you intend
  to run.

## Development & linting

```bash
yamllint .
ansible-lint                 # passes the 'production' profile
ansible-galaxy collection build
```

Lint configuration lives in [`.yamllint`](.yamllint) and
[`.ansible-lint`](.ansible-lint).

## License

Apache-2.0. See [LICENSE](LICENSE).
