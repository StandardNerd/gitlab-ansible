# Role: `ro_gitlab_runner`

Install and configure a **GitLab Runner** on a target VM, running the runner process inside a **Podman** container with optional systemd integration for boot persistence.

---

## Requirements

### Control Node

| Requirement | Minimum version |
|---|---|
| Ansible | 2.14+ |
| Python | 3.9+ |

### Ansible Collections (install before use)

```bash
ansible-galaxy collection install containers.podman community.general ansible.posix
```

Or add to your `requirements.yml`:

```yaml
collections:
  - name: containers.podman
    version: ">=1.10.0"
  - name: community.general
    version: ">=6.0.0"
  - name: ansible.posix
    version: ">=1.5.0"
```

### Target Host

- RHEL 9/10, Rocky/Alma Linux, Ubuntu 22.04/24.04, Debian 12, or openSUSE/SLES
- `sudo` / root access (`ansible_become: true`)
- Network access to:
  - Your GitLab instance (for runner registration)
  - A container registry (default: `docker.io`) to pull the runner image

---

## Role Variables

All variables have defaults defined in [`defaults/main.yml`](defaults/main.yml).

### GitLab Connection

| Variable | Default | Description |
|---|---|---|
| `gitlab_url` | `http://gitlab.example.com` | URL of the GitLab instance |
| `gitlab_runner_registration_token` | `REPLACE_ME` | Registration token from **Admin > CI/CD > Runners** — store in Ansible Vault |
| `gitlab_runner_token` | `""` | Pre-existing runner authentication token. When set, registration is skipped |

> [!CAUTION]
> Never store `gitlab_runner_registration_token` in plaintext. Use `ansible-vault encrypt_string` or a vault file.

### Runner Identity

| Variable | Default | Description |
|---|---|---|
| `gitlab_runner_name` | `{{ inventory_hostname }}-podman` | Human-readable runner name in GitLab UI |
| `gitlab_runner_tags` | `podman` | Comma-separated job tags |
| `gitlab_runner_run_untagged` | `true` | Pick up untagged jobs |
| `gitlab_runner_locked` | `false` | Lock runner to a single project |

### Concurrency & Polling

| Variable | Default | Description |
|---|---|---|
| `gitlab_runner_concurrent` | `4` | Max simultaneous jobs across all executors |
| `gitlab_runner_check_interval` | `3` | GitLab polling interval in seconds |

### Executor

| Variable | Default | Description |
|---|---|---|
| `gitlab_runner_executor` | `shell` | Executor type: `shell`, `docker`, `docker+machine`, `custom` |
| `gitlab_runner_default_image` | `alpine:latest` | Default image for `docker` executor |
| `gitlab_runner_privileged` | `false` | Enable privileged mode (needed for DinD/PinP) |
| `gitlab_runner_volumes` | `["/cache"]` | Extra volumes for `docker` executor |

### Podman / Container

| Variable | Default | Description |
|---|---|---|
| `gitlab_runner_image` | `docker.io/gitlab/gitlab-runner:latest` | OCI image for the runner |
| `gitlab_runner_container_name` | `gitlab-runner` | Podman container name |
| `gitlab_runner_config_dir` | `/etc/gitlab-runner` | Host directory for `config.toml` (bind-mounted) |
| `gitlab_runner_builds_dir` | `/var/lib/gitlab-runner/builds` | Host directory for build workspaces |
| `gitlab_runner_cache_dir` | `/var/lib/gitlab-runner/cache` | Host directory for runner cache |
| `gitlab_runner_enable_podman_socket` | `true` | Expose Podman socket into the container |
| `gitlab_runner_container_user` | `""` | Run container as specific UID:GID |
| `gitlab_runner_container_env` | `[]` | Extra environment variables (`KEY=VALUE` list) |
| `gitlab_runner_restart_policy` | `always` | Podman restart policy |

### Systemd

| Variable | Default | Description |
|---|---|---|
| `gitlab_runner_systemd_enabled` | `true` | Generate and enable a systemd unit for the container |
| `gitlab_runner_systemd_service` | `container-gitlab-runner` | Systemd service unit name |

### Logging

| Variable | Default | Description |
|---|---|---|
| `gitlab_runner_log_level` | `info` | Runner log level (`debug`, `info`, `warn`, `error`) |
| `gitlab_runner_log_format` | `runner` | Log format (`runner`, `text`, `json`) |

---

## Dependencies

None (no Ansible Galaxy role dependencies). See [Requirements](#requirements) for collection dependencies.

---

## Example Playbooks

### Minimal — shell executor

```yaml
- name: Deploy GitLab Runner
  hosts: runner_hosts
  become: true
  vars_files:
    - vault/runner_secrets.yml   # contains gitlab_runner_registration_token
  roles:
    - role: ro_gitlab_runner
      vars:
        gitlab_url: "https://gitlab.example.com"
        gitlab_runner_name: "rhel-podman-runner"
        gitlab_runner_tags: "podman,rhel"
```

### Docker executor with Podman socket

```yaml
- name: Deploy GitLab Runner (docker executor via Podman)
  hosts: runner_hosts
  become: true
  roles:
    - role: ro_gitlab_runner
      vars:
        gitlab_url: "https://gitlab.example.com"
        gitlab_runner_registration_token: "{{ vault_runner_token }}"
        gitlab_runner_executor: "docker"
        gitlab_runner_default_image: "alpine:3.19"
        gitlab_runner_privileged: false
        gitlab_runner_enable_podman_socket: true
        gitlab_runner_container_env:
          - "DOCKER_HOST=unix:///run/podman/podman.sock"
```

### Multiple concurrent jobs, custom image

```yaml
- name: Deploy high-throughput GitLab Runner
  hosts: runner_hosts
  become: true
  roles:
    - role: ro_gitlab_runner
      vars:
        gitlab_url: "https://gitlab.example.com"
        gitlab_runner_registration_token: "{{ vault_runner_token }}"
        gitlab_runner_name: "build-farm-01"
        gitlab_runner_concurrent: 16
        gitlab_runner_check_interval: 1
        gitlab_runner_image: "docker.io/gitlab/gitlab-runner:v17.3.0"
        gitlab_runner_executor: "shell"
        gitlab_runner_tags: "podman,build,linux"
        gitlab_runner_run_untagged: false
```

---

## Role Structure

```text
ro_gitlab_runner/
├── defaults/
│   └── main.yml          # All user-configurable variables with defaults
├── vars/
│   └── main.yml          # Internal role variables (OS package maps, paths)
├── tasks/
│   ├── main.yml          # Entry point — orchestrates phase includes
│   ├── assert.yml        # Pre-flight variable validation
│   ├── install_podman.yml # Multi-distro Podman installation
│   ├── configure.yml     # Directory creation and config.toml rendering
│   ├── container.yml     # Image pull and container lifecycle
│   ├── register.yml      # Idempotent GitLab registration
│   └── systemd.yml       # Systemd unit generation and enablement
├── templates/
│   └── config.toml.j2    # GitLab Runner config template
├── handlers/
│   └── main.yml          # Container restart and systemd reload handlers
├── meta/
│   └── main.yml          # Galaxy metadata and collection requirements
└── tests/
    ├── inventory         # Localhost inventory for smoke tests
    └── test.yml          # Smoke-test playbook
```

---

## Idempotency Notes

| Operation | How idempotency is achieved |
|---|---|
| Podman install | `state: present` on package modules |
| Config directory creation | `state: directory` with `ansible.builtin.file` |
| `config.toml` render | Only written when file does not yet exist |
| Container creation | `containers.podman.podman_container` is idempotent by design |
| Image update | Container is re-created only when the image digest changes |
| Runner registration | `config.toml` is parsed for an existing token before `register` is called |
| Systemd unit | `enabled: true` / `state: started` are no-ops when already in that state |

---

## OS Compatibility

| OS Family | Package Manager | Packages Installed |
|---|---|---|
| RHEL / Rocky / AlmaLinux | `dnf` | `podman`, `podman-plugins`, `slirp4netns`, `fuse-overlayfs` |
| Ubuntu / Debian | `apt` | `podman`, `uidmap`, `slirp4netns`, `fuse-overlayfs` |
| openSUSE / SLES | `zypper` | `podman` |

---

## Security Considerations

- The runner registration token is treated as a secret (`no_log: true` on the registration task).  
- Always store `gitlab_runner_registration_token` in an **Ansible Vault** file.  
- Avoid `gitlab_runner_privileged: true` unless your pipelines explicitly need it (DinD / PinP).  
- The Podman socket gives container workloads elevated container management rights — scope access with SELinux labels (`:Z`) as configured by the role.

---

## Integration with the Existing Project

Add runner hosts to your inventory and call the new playbook:

```yaml
# inventory/hosts.yml
all:
  children:
    runner_hosts:
      hosts:
        runner01:
          ansible_host: 10.10.10.20
          ansible_user: ansible
          ansible_become: true
```

```bash
# Encrypt the registration token
ansible-vault encrypt_string 'glrt-xxxx' --name 'runner_registration_token' >> credentials.yml

# Run the playbook
ansible-playbook pb_gitlab_runner.yml \
  -i inventory/hosts.yml \
  -l runner_hosts \
  --ask-vault-pass
```

---

## License

MIT-0

## Author Information

Part of the [gitlab-ansible](https://github.com/your-org/gitlab-ansible) automation project.
