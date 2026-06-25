# Reaching hosts through a jump host (bastion)

The Teleport Auth/Proxy nodes in these environments are not reachable directly
from the controller (laptop, CI runner, or AAP execution environment). They sit
behind a **jump host / bastion**. This is the bootstrap problem: before Teleport
exists, the *only* way in is plain SSH through that bastion.

**You do not need a custom `~/.ssh/config` for this.** Ansible solves it natively
at the inventory layer, which is the recommended approach because the connection
topology is then version-controlled next to the hosts it describes and works
identically from a laptop, CI, and an AAP execution environment.

## Recommended: `ProxyJump` via `ansible_ssh_common_args`

This collection wires it in each environment's `group_vars` (see
`playbooks/inventory/group_vars/hw01.yml`), behind a `teleport_use_bastion`
toggle so the same codebase can connect directly where no jump host is needed
(e.g. AAP — see below):

```yaml
teleport_bastion: "bastion@jump.hw01.example.com"
teleport_use_bastion: true
ansible_ssh_common_args: >-
  {{ ('-o ProxyJump=' ~ teleport_bastion ~ ' -o CheckHostIP=no -o StrictHostKeyChecking=accept-new')
     if (teleport_use_bastion | bool) else '' }}
```

`ansible_ssh_common_args` is appended to every `ssh`/`scp`/`sftp` Ansible runs,
so it applies to the connection *and* to file transfers. `ProxyJump` (OpenSSH
7.3+) opens the connection to the target **through** the bastion in a single
hop. `CheckHostIP=no` is explained under *Same target IPs* below. Edit
`teleport_bastion` per environment and run as usual:

```bash
ansible-playbook -i playbooks/inventory/hw01.yml playbooks/site.yml
```

### Why `ProxyJump` and not "ssh to bastion, then ssh to host"

- **No key on the bastion.** Authentication to the *target* happens from the
  controller, tunneled through the bastion. Your private key never lands on the
  jump host (unlike the manual two-hop flow). The bastion only needs to let you
  open a forwarded channel.
- **One declarative line**, applied uniformly to every host in the group.
- **Same behavior everywhere** — laptop, CI, and EE/AAP.

## Host-key checking and the bootstrap moment

On the very first connect, neither the bastion nor the target host keys are
known. Options, from most convenient to most strict:

- `StrictHostKeyChecking=accept-new` (used above) — trust-on-first-use: accept
  unknown keys, but still fail if a *known* key changes. Good default for
  bootstrapping fleets.
- Pre-seed `known_hosts` (most secure): collect keys via the bastion and commit
  them, then drop `accept-new`:
  ```bash
  ssh -J bastion@jump.hw01.example.com auth1.hw01.example.com 'true'   # populates ~/.ssh/known_hosts
  ```
- `-o UserKnownHostsFile=...` to point at a repo-managed known_hosts file.

Avoid `StrictHostKeyChecking=no` (blindly trusts everything, including changed
keys).

## Same target IPs across environments

If two environments reuse the **same target IP addresses** but reach different
physical hosts through different bastions (e.g. `10.0.0.10` via `jump.hw01` vs
`10.0.0.10` via `jump.dev02`), `known_hosts` collides: ssh keys host entries by
IP, so the second environment presents a *different* key for an *already known*
IP and ssh rejects it as a changed key (a suspected MITM). `accept-new` does not
help — the IP is not "new". The symptom is `Connection closed by UNKNOWN port
65535` (the ProxyJump inner hop being torn down).

The fix used here is **`-o CheckHostIP=no`**, so ssh verifies by **hostname
only** (which is unique per environment, e.g. `auth1.hw01…` vs `auth1.dev02…`)
and never records the shared IP. Connect by the unique FQDN (set `ansible_host`
to the name, or leave it unset), not the shared IP.

If you can *only* dial the shared IP, give each environment its own
`-o UserKnownHostsFile=/abs/path/known_hosts.<env>` instead — but use an
absolute path and pre-seed it (an empty file plus ProxyJump can fail to write
under `accept-new`).

## Authentication options

- **SSH agent (recommended):** run `ssh-add` locally; the agent answers
  challenges through the tunnel. The bundled `execution-environment/ansible-navigator.yml`
  already forwards `SSH_AUTH_SOCK` into the EE.
- **Explicit key:** `ansible_ssh_private_key_file` for the target, plus
  `-o IdentityFile=...` inside `ProxyJump` if the bastion needs a different key:
  ```yaml
  ansible_ssh_common_args: >-
    -o ProxyJump={{ teleport_bastion }}
    -o IdentityFile=~/.ssh/id_bastion
  ```

## Multiple hops

`ProxyJump` chains: `-o ProxyJump=user@jump1,user@jump2`.

## Older OpenSSH (< 7.3): `ProxyCommand`

If `ProxyJump` is unavailable, use the equivalent netcat-style command:

```yaml
ansible_ssh_common_args: >-
  -o ProxyCommand="ssh -W %h:%p -q {{ teleport_bastion }}"
```

## The `~/.ssh/config` alternative

A static `~/.ssh/config` works too:

```sshconfig
Host auth1.hw01.example.com proxy1.hw01.example.com
    ProxyJump bastion@jump.hw01.example.com

Host jump.hw01.example.com
    User bastion
```

Ansible will honor it because it shells out to the system `ssh`. It is fine for
a single operator, but it lives outside the repo (so teammates, CI, and EEs do
not get it automatically). Prefer the inventory variable; reserve `ssh_config`
for personal convenience or for settings you don't want in version control.

## Running inside AAP / Automation Controller

AAP usually has **direct routing** to the nodes, so the bastion isn't needed.
Whether the `ProxyJump` applies there depends entirely on the **inventory
source**, and `ansible_ssh_common_args` is not skipped by magic:

- `group_vars/` are loaded **relative to the inventory you run**. Locally you
  pass `-i playbooks/inventory/hw01.yml`, so the adjacent `group_vars/hw01.yml`
  loads and the bastion applies.
- In AAP the job runs against a **Controller inventory** (entered in the UI or
  synced from another source). That's a *different source*, so the repo's
  adjacent `group_vars` are not read — and the bastion simply isn't there.
- **Caveat:** if the Controller inventory is *"Sourced from a Project"* pointing
  at `playbooks/inventory/hw01.yml`, the adjacent `group_vars` **do** load, and
  AAP would try to ProxyJump through an unreachable bastion.

Make it explicit rather than relying on that, via the `teleport_use_bastion`
toggle:

- Set `teleport_use_bastion: false` on AAP — as a **Job Template variable**
  (extra var, highest precedence) or a **Controller inventory/group variable**.
  The rendered `ansible_ssh_common_args` becomes empty and the connection is
  direct, while local runs keep `teleport_use_bastion: true`.
- Or override bluntly with the Job Template extra var
  `ansible_ssh_common_args: ""`.

Other AAP notes:

- Attach a **Machine credential** for the target SSH user (key or vault).
- When you *do* use a bastion from AAP, ensure the EE can verify host keys
  (pre-seed `known_hosts` baked into the EE, or keep `accept-new` for bootstrap),
  and if the bastion needs a *different* credential, reference its key with
  `IdentityFile` inside `ProxyJump`.
