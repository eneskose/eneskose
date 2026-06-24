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
`playbooks/inventory/group_vars/hw01.yml`):

```yaml
teleport_bastion: "bastion@jump.hw01.example.com"
ansible_ssh_common_args: >-
  -o ProxyJump={{ teleport_bastion }}
  -o StrictHostKeyChecking=accept-new
```

`ansible_ssh_common_args` is appended to every `ssh`/`scp`/`sftp` Ansible runs,
so it applies to the connection *and* to file transfers. `ProxyJump` (OpenSSH
7.3+) opens the connection to the target **through** the bastion in a single
hop. Edit `teleport_bastion` per environment and run as usual:

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

The same `ansible_ssh_common_args` in `group_vars` is the cleanest path:

- Attach a **Machine credential** for the target SSH user (key or vault).
- The `ProxyJump` line travels with the inventory, so jobs proxy through the
  bastion with no per-job configuration.
- Ensure the EE can verify host keys: either pre-seed a `known_hosts` mounted/
  baked into the EE, or keep `accept-new` for bootstrap.
- If the bastion needs a *different* credential than the targets, add its key to
  the EE/agent and reference it with `IdentityFile` inside `ProxyJump`.
