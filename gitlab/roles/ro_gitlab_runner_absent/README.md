# ro_gitlab_runner_absent

Ansible role to cleanly unregister, stop, and decommission a **GitLab Runner** deployed via a **Podman container** on RHEL 9 or Ubuntu Noble (24.04) hosts.

This role serves as the teardown counterpart to [`ro_gitlab_runner`](../ro_gitlab_runner). It gracefully unregisters runners from the GitLab instance, removes systemd service units and container runtime artifacts, purges configuration and data directories, and can optionally remove the container image and uninstall Podman packages.

---

## Requirements

### Control Node
- **Ansible**: `>= 2.14`
- **Ansible Collections**:
  - `containers.podman` (for Podman container and image removal)
  - `ansible.builtin`

### Target Host
- **Supported Operating Systems**:
  - **Ubuntu 24.04 (Noble Numbat)** / Debian 12 (Bookworm)
  - **RHEL 9** / Rocky Linux 9 / AlmaLinux 9
- Privileged access (`become: true` / root)

---

## What It Does

| Phase | Task File | Description |
| :--- | :--- | :--- |
| **0. Assert** | `assert.yml` | Validates required role variables and non-empty paths |
| **1. Unregister** | `unregister.yml` | Extracts registration token from `config.toml` and calls `gitlab-runner unregister --all-runners` inside the running container (or via an ephemeral container if already stopped) |
| **2. Systemd** | `systemd.yml` | Stops and disables `container-gitlab-runner.service`, removes the unit file and `.ctr-id`, reloads systemd daemon, and resets failed unit state |
| **3. Container** | `container.yml` | Stops and removes the `gitlab-runner` container; optionally deletes the runner OCI image from local Podman storage |
| **4. Cleanup** | `cleanup.yml` | Deletes host directories: `/etc/gitlab-runner` (config, certs) and `/var/lib/gitlab-runner` (cache, builds) |
| **5. Podman** | `uninstall_podman.yml` | *(Optional)* Disables `podman.socket`, uninstalls Podman package dependencies, and cleans `/etc/containers` |

---

## Role Variables

Variables can be customized in inventory `host_vars`/`group_vars`, playbook `vars`, or passed as extra-vars (`-e`).

### Connection & Target Instance

| Variable | Default | Description |
| :--- | :--- | :--- |
| `gitlab_url` | `https://192.168.1.129` | URL of the GitLab server where the runner is registered |

### Container & Service Identity

| Variable | Default | Description |
| :--- | :--- | :--- |
| `glra_container_name` | `gitlab-runner` | Name of the Podman container running the runner |
| `glra_runner_image` | `docker.io/gitlab/gitlab-runner:latest` | OCI image used by the runner container |
| `glra_systemd_service` | `container-{{ glra_container_name }}` | Name of the generated systemd service unit |

### Host Directories

| Variable | Default | Description |
| :--- | :--- | :--- |
| `glra_config_dir` | `/etc/gitlab-runner` | Host directory containing `config.toml` and TLS certificates |
| `glra_builds_dir` | `/var/lib/gitlab-runner/builds` | Host directory for CI/CD job workspace builds |
| `glra_cache_dir` | `/var/lib/gitlab-runner/cache` | Host directory for runner cache storage |

### Decommissioning & Removal Controls

| Variable | Default | Description |
| :--- | :--- | :--- |
| `glra_unregister` | `true` | Unregister runner instances from GitLab before removing container |
| `glra_remove_data` | `true` | Purge configuration, TLS certs, builds, and cache directories from the host |
| `glra_remove_image` | `true` | Remove the GitLab Runner OCI image from local Podman image store |
| `glra_remove_podman` | `false` | Completely uninstall Podman and its OS dependencies (`dnf` or `apt purge`) |
| `glra_remove_podman_socket` | `false` | Stop and disable the `podman.socket` systemd unit |

---

## Usage Examples

### 1. Standard Decommissioning Playbook

A typical playbook to decommission the runner and wipe container data:

```yaml
---
- name: "Decommission GitLab Runner (Podman)"
  hosts: gitlab-runner
  become: true
  vars_files:
    - ./credentials.yml
  roles:
    - role: ro_gitlab_runner_absent
```

Execute via CLI:

```bash
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml
```

### 2. Decommission Runner but Preserve Build & Cache Data

If you need to replace or reinstall the container while retaining downloaded build caches:

```bash
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml \
  -e "glra_remove_data=false"
```

### 3. Complete Host Teardown (Including Podman Packages)

To decommission the runner and completely remove Podman, container storage, and sockets:

```bash
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml \
  -e "glra_remove_podman=true" \
  -e "glra_remove_podman_socket=true"
```

### 4. Skip Unregistration (Server Unreachable / Decommissioned)

If the GitLab server has already been taken offline or wiped, unregistration attempts would fail. You can skip the API unregistration:

```bash
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml \
  -e "glra_unregister=false"
```

---

## Role Structure

```text
ro_gitlab_runner_absent/
├── defaults/
│   └── main.yml                  # Configurable role parameters and defaults
├── vars/
│   ├── main.yml                  # Internal paths and directories list
│   ├── RedHat.yml                # RHEL-specific Podman packages
│   └── Debian.yml                # Debian/Ubuntu-specific Podman packages
├── tasks/
│   ├── main.yml                  # Role orchestrator and execution entry point
│   ├── assert.yml                # Variable validation and assertions
│   ├── unregister.yml            # Graceful unregistration (active or stopped container)
│   ├── systemd.yml               # Service stop, unit removal, reset-failed
│   ├── container.yml             # Podman container and image removal
│   ├── cleanup.yml               # Host directory and data purge
│   └── uninstall_podman.yml      # Optional Podman package uninstallation
├── handlers/
│   └── main.yml                  # Systemd daemon-reload handler
├── meta/
│   └── main.yml                  # Galaxy metadata and platform support
├── tests/
│   ├── inventory                 # Test inventory
│   └── test.yml                  # Test playbook
└── README.md                     # Role documentation
```

---

## Idempotency & Failure Tolerance

- **Graceful Unregistration**: If the runner container is stopped or has exited, the role automatically launches a temporary one-off container with `/etc/gitlab-runner` bind-mounted to execute `gitlab-runner unregister --all-runners`. If the server is unreachable, the task logs the warning and continues without failing.
- **Service Cleanup**: Systemd unit removal handles missing unit files gracefully (`failed_when: false`) and runs `systemctl reset-failed` to prevent orphaned failed unit states in systemd.
- **Directory Purge**: Directory deletion using `ansible.builtin.file` with `state: absent` is inherently idempotent.
- **Re-runs**: Running the playbook multiple times against an already decommissioned node executes cleanly with `changed=0` and `failed=0`.

---

## Security Considerations

- **Server Tokens**: Unregistration removes the runner's authentication token from GitLab, ensuring stale runners do not remain visible or pollable in the GitLab Admin Console.
- **Credential Storage**: When running the playbook, ensure sensitive SSH passwords or become passwords are encrypted using **Ansible Vault** (`credentials.yml`).

---

## License

MIT-0

## Author Information

Part of the gitlab-ansible automation project.
