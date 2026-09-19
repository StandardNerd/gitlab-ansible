# ro_gitlab_runner

Ansible role to install, configure, and register a **GitLab Runner** executing via a **Podman container**.

This role configures the target host as a Podman host, runs the GitLab Runner binary inside a dedicated Podman container, and can optionally expose the rootless/root Podman socket back to the runner so that CI/CD jobs can run as native containers (the `docker` executor mapped to Podman).

## Requirements

- Control node:
  - Ansible >= 2.14
  - Collections:
    - `containers.podman` (for container lifecycle)
    - `ansible.posix` (for SELinux booleans)
- Target host:
  - **RHEL 9** (or clones like Rocky Linux 9, AlmaLinux 9)
  - **Ubuntu 24.04 (Noble)**

## Role Variables

Variables can be overridden in inventory or via extra-vars. For sensitive variables (like tokens), use **Ansible Vault**.

### Connection & Registration

| Variable | Default | Description |
|---|---|---|
| `gitlab_url` | `http://gitlab.example.com` | URL of the target GitLab instance |
| `gitlab_runner_registration_token` | `REPLACE_ME` | Registration token from **Admin > CI/CD > Runners** — store in Ansible Vault |
| `gitlab_runner_token` | `""` | Pre-existing runner authentication token. When set, registration is skipped |

### OS-Specific Security

| Variable | Default | Description |
|---|---|---|
| `gitlab_runner_configure_selinux` | `true` | Configure SELinux boolean `container_manage_cgroup` for Podman on RHEL |
| `gitlab_runner_configure_apparmor` | `true` | Ensure AppArmor service is enabled and running on Ubuntu |

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

### Docker executor with Podman socket (Ubuntu Noble / RHEL 9)

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

---

## Role Structure

```text
ro_gitlab_runner/
├── defaults/
│   └── main.yml                  # All user-configurable variables with defaults
├── vars/
│   ├── main.yml                  # Internal shared variables
│   ├── RedHat.yml                # RHEL-specific variables (packages, SELinux)
│   └── Debian.yml                # Debian/Ubuntu-specific variables (packages, AppArmor)
├── tasks/
│   ├── main.yml                  # Entry point — orchestrates phase includes
│   ├── assert.yml                # Pre-flight variable validation
│   ├── install_podman_redhat.yml # RHEL 9 Podman and SELinux installation
│   ├── install_podman_debian.yml # Ubuntu 24.04 Podman and AppArmor installation
│   ├── configure.yml             # Directory creation and config.toml rendering
│   ├── container.yml             # Image pull and container lifecycle
│   ├── register.yml              # Idempotent GitLab registration
│   └── systemd.yml               # Systemd unit generation and enablement
├── templates/
│   └── config.toml.j2            # GitLab Runner config template
├── handlers/
│   └── main.yml                  # Container restart and systemd reload handlers
├── meta/
│   └── main.yml                  # Galaxy metadata and collection requirements
└── molecule/                     # Molecule testing setup
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

## Security Considerations

- The runner registration token is treated as a secret (`no_log: true` on the registration task).  
- Always store `gitlab_runner_registration_token` in an **Ansible Vault** file.  
- Avoid `gitlab_runner_privileged: true` unless your pipelines explicitly need it (DinD / PinP).  
- The Podman socket gives container workloads elevated container management rights — scope access with SELinux labels (`:Z`) as configured by the role on RHEL, or utilize AppArmor profiles on Ubuntu.

---

## License

MIT-0

## Author Information

Part of the gitlab-ansible automation project.
