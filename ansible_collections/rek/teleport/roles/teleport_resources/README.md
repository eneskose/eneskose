# Role: `rek.teleport.teleport_resources`

Manages Teleport **dynamic resources** — RBAC roles, SSO connectors,
`cluster_auth_preference`, users, etc. — by applying complete resource documents
to the Auth server with `tctl`. These are *not* part of `teleport.yaml`; they
live in the cluster and are managed via the API.

Run it on an **Auth node** with privilege (`become: true`); it uses the local
admin socket, so no SSO/credentials are required. The bundled
`playbooks/resources.yml` targets `teleport_auth` and applies once.

## How it works

Each variable holds **complete resource documents** (`kind`, `version`,
`metadata`, `spec`), so the role is schema/version-agnostic — copy specs
straight from the Teleport docs. Resources are applied in dependency order:

1. `teleport_roles` (RBAC) — first, so connectors can reference them
2. `teleport_sso_connectors` (github / saml / oidc) — applied with `no_log`
3. `teleport_auth_preference` (single `cluster_auth_preference`)
4. `teleport_resources_extra` (users, login_rules, access_lists, …)

Each document is rendered to a `0600` file in a temporary directory and applied
with `tctl create --force -f <file>` (upsert), then the directory is removed.

## Idempotency & limitations

- **Upsert on every run.** Tasks report `changed` whenever they apply; `--check`
  is a no-op (nothing is modified).
- **No pruning.** Removing an item from the variables does **not** delete it
  from the cluster — delete it manually (`tctl rm role/<name>`) or use Teleport's
  Terraform provider / Kubernetes operator if you need full declarative
  lifecycle with drift detection.
- **Edition:** `saml`/`oidc` connectors require Teleport **Enterprise**; the
  `github` connector also works on OSS.

## Variables

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `teleport_roles` | list[dict] | `[]` | `role` resource documents |
| `teleport_sso_connectors` | list[dict] | `[]` | github/saml/oidc connector documents |
| `teleport_auth_preference` | dict | `{}` | single `cluster_auth_preference` document |
| `teleport_resources_extra` | list[dict] | `[]` | any other resource documents |

Keep the actual values in (vaulted) `group_vars`, scoped per environment when
connectors/secrets differ — same pattern as the license and inventory.

## Example (group_vars, secrets vaulted)

```yaml
# RBAC role
teleport_roles:
  - kind: role
    version: v7
    metadata: {name: ssh-access}
    spec:
      allow:
        logins: ["{{ '{{internal.logins}}' }}"]
        node_labels: {"*": "*"}

# GitHub SSO connector (client secret from vault)
teleport_sso_connectors:
  - kind: github
    version: v3
    metadata: {name: github}
    spec:
      client_id: "Iv1.0123456789abcdef"
      client_secret: "{{ vault_teleport_github_client_secret }}"
      redirect_url: "https://teleport.hw01.example.com:443/v1/webapi/github/callback"
      teams_to_roles:
        - {organization: my-org, team: admins, roles: ["access", "editor"]}

# Make GitHub the default login method
teleport_auth_preference:
  kind: cluster_auth_preference
  version: v2
  metadata: {name: cluster-auth-preference}
  spec:
    type: github
    second_factor: webauthn
    webauthn: {rp_id: teleport.hw01.example.com}
```

## Usage

```bash
ansible-playbook -i playbooks/inventory/hw01.yml playbooks/resources.yml --ask-vault-pass
```

Apply after the cluster is up (`site.yml`). Define `teleport_roles` before any
connector that references them (the role already orders the apply steps).
