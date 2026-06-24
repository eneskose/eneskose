# Execution Environment — `rek.teleport`

An [Ansible Execution Environment](https://ansible.readthedocs.io/projects/builder/en/latest/)
(EE) that bundles the `rek.teleport` collection so the Teleport roles run
identically from the CLI ([`ansible-navigator`](https://ansible.readthedocs.io/projects/navigator/))
and from **Ansible Automation Platform / Automation Controller (AAC)**.

## Contents

| File | Purpose |
|------|---------|
| `execution-environment.yml` | `ansible-builder` v3 image definition |
| `requirements.yml` | Collections baked into the image (bundles `rek.teleport`) |
| `requirements.txt` | Extra Python deps (none today) |
| `bindep.txt` | OS packages (the SSH client) |
| `ansible-navigator.yml` | Navigator settings (points at the EE image) |
| `build.sh` | Rebuilds the collection tarball + builds the image |

The image is based on `quay.io/ansible/awx-ee` (ships `ansible-core`,
`ansible-runner`, Python and `dnf`). For a Red&nbsp;Hat-supported AAP image,
switch `base_image` to `ee-minimal-rhel9` — see the comment in
`execution-environment.yml`.

## Build

Requires `ansible-builder` and a container runtime (`podman` by default, or set
`CONTAINER_RUNTIME=docker`).

```bash
cd execution-environment
./build.sh                       # -> rek/teleport-ee:1.0.0
./build.sh quay.io/myorg/rek-teleport-ee:1.0.0   # custom tag to push
```

`build.sh` rebuilds the collection tarball from `../ansible_collections/rek/teleport`
before each build, so the image always reflects the current source. To build by
hand instead, run `ansible-galaxy collection build ../ansible_collections/rek/teleport
--output-path . --force` first, then `ansible-builder build -f execution-environment.yml
-t rek/teleport-ee:1.0.0`.

## Run with ansible-navigator

```bash
cd execution-environment
ansible-navigator run ../ansible_collections/rek/teleport/playbooks/site.yml \
  -i ../ansible_collections/rek/teleport/playbooks/inventory/hosts.yml
```

Navigator reads `ansible-navigator.yml` from the current directory, so it uses
the `rek/teleport-ee:1.0.0` image automatically and forwards `SSH_AUTH_SOCK`
for agent-based auth. Add `--syntax-check` for a quick smoke test.

## Use in Automation Controller (AAC)

1. Push the image to a registry your Controller can reach:
   ```bash
   ./build.sh quay.io/myorg/rek-teleport-ee:1.0.0
   podman push quay.io/myorg/rek-teleport-ee:1.0.0
   ```
2. In the Controller UI: **Administration → Execution Environments → Add**, set
   the image to `quay.io/myorg/rek-teleport-ee:1.0.0` (attach a registry
   credential if private).
3. Select this EE on the Job Template that runs `site.yml` / `auth.yml` /
   `proxy.yml`.

To have Controller build the EE from source control instead of bundling a
tarball, switch `requirements.yml` to the Git entry documented inside that file.

## Notes

- `context/` and `rek-teleport-*.tar.gz` are build artifacts (git-ignored);
  `build.sh` regenerates them.
- The roles only use `ansible.builtin` modules, so the EE needs no extra Python
  libraries — just the SSH client (`bindep.txt`) to reach managed nodes.
