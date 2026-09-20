# ro_gitlab_runner

Ansible role to install, configure, trust TLS certificates, and register a **GitLab Runner** executing via a **Podman container** on RHEL 9 or Ubuntu Noble (24.04) hosts.

This role provisions the target host with Podman, runs the official GitLab Runner container image inside a managed container, automatically fetches and trusts self-signed server TLS certificates (including Subject Alternative Names), registers the runner with the GitLab instance, and configures a persistent systemd service unit (`container-gitlab-runner.service`).

---

## Requirements

### Control Node
- **Ansible**: `>= 2.14`
- **Ansible Collections**:
  - `containers.podman` (for container and image lifecycle)
  - `ansible.posix` (for SELinux booleans on RHEL)
  - `ansible.builtin`

### Target Host
- **Supported Operating Systems**:
  - **Ubuntu 24.04 (Noble Numbat)** / Debian 12 (Bookworm)
  - **RHEL 9** / Rocky Linux 9 / AlmaLinux 9
- Privileged access (`become: true` / root)

---

## Role Variables

Variables can be overridden in inventory `host_vars`/`group_vars`, playbook `vars`, or via extra-vars (`-e`). Sensitive tokens should always be encrypted using **Ansible Vault**.

### Connection & Registration

| Variable | Default | Description |
| :--- | :--- | :--- |
| `gitlab_url` | `https://192.168.1.129` | URL of the target GitLab instance |
| `gitlab_runner_registration_token` | `4gcyYJNxXUxMZKji5WpA` | Instance registration token from GitLab (**Admin > CI/CD > Runners**) |
| `gitlab_runner_token` | `""` | Optional pre-existing runner authentication token (`glrt-...`). When set, registration is skipped |

### Runner Identity

| Variable | Default | Description |
| :--- | :--- | :--- |
| `gitlab_runner_name` | `{{ inventory_hostname }}-podman` | Human-readable runner name displayed in the GitLab UI |
| `gitlab_runner_tags` | `podman` | Comma-separated tags used by CI/CD pipeline jobs to target this runner |
| `gitlab_runner_run_untagged` | `true` | When `true`, runner picks up jobs without specific tags |
| `gitlab_runner_locked` | `false` | When `true`, the runner is locked to the specific registration project |

### Concurrency & Polling

| Variable | Default | Description |
| :--- | :--- | :--- |
| `gitlab_runner_concurrent` | `4` | Maximum number of simultaneous CI/CD jobs across all executors |
| `gitlab_runner_check_interval` | `3` | Interval (in seconds) between polling GitLab for new jobs |

### Executor Configuration

| Variable | Default | Description |
| :--- | :--- | :--- |
| `gitlab_runner_executor` | `shell` | Executor type: `shell`, `docker`, `docker+machine`, or `custom` |
| `gitlab_runner_default_image` | `alpine:latest` | Default base container image when using `docker` executor |
| `gitlab_runner_privileged` | `false` | Run CI job containers in privileged mode (required for Docker-in-Docker / DinD) |
| `gitlab_runner_volumes` | `["/cache"]` | Extra volumes mounted into **CI job containers** when using `docker` executor |

### Podman & Runner Container

| Variable | Default | Description |
| :--- | :--- | :--- |
| `gitlab_runner_image` | `docker.io/gitlab/gitlab-runner:latest` | OCI image used for the runner container |
| `gitlab_runner_container_name` | `gitlab-runner` | Name of the Podman container running the runner daemon |
| `gitlab_runner_config_dir` | `/etc/gitlab-runner` | Host directory bind-mounted into container as `/etc/gitlab-runner` |
| `gitlab_runner_builds_dir` | `/var/lib/gitlab-runner/builds` | Host directory for build workspaces (bind-mounted as `/builds:Z`) |
| `gitlab_runner_cache_dir` | `/var/lib/gitlab-runner/cache` | Host directory for runner cache (bind-mounted as `/cache:Z`) |
| `gitlab_runner_extra_volumes` | `[]` | Extra host volumes mounted into the **runner container itself** |
| `gitlab_runner_enable_podman_socket` | `true` | Mounts `/run/podman/podman.sock` into container for Docker-compatible execution |
| `gitlab_runner_container_user` | `""` | Run container process as a specific UID:GID (empty string uses image default) |
| `gitlab_runner_container_env` | `[]` | List of `KEY=VALUE` environment variables passed to runner container |
| `gitlab_runner_restart_policy` | `always` | Podman container restart policy (`always`, `on-failure`, `no`) |

### Systemd Integration

| Variable | Default | Description |
| :--- | :--- | :--- |
| `gitlab_runner_systemd_enabled` | `true` | Generate, enable, and start a systemd unit for the container |
| `gitlab_runner_systemd_service` | `container-{{ gitlab_runner_container_name }}` | Name of the generated systemd service unit |

### OS-Specific Security & Firewalls

| Variable | Default | Description |
| :--- | :--- | :--- |
| `gitlab_runner_configure_selinux` | `true` | Configure SELinux boolean `container_manage_cgroup` for Podman on RHEL |
| `gitlab_runner_configure_apparmor` | `true` | Ensure AppArmor service is enabled and running on Ubuntu/Debian |
| `gitlab_runner_configure_firewall` | `false` | Configure outbound firewall rules (usually not needed as runner initiates connection) |

### Logging & Debugging

| Variable | Default | Description |
| :--- | :--- | :--- |
| `gitlab_runner_log_level` | `info` | Log verbosity (`debug`, `info`, `warn`, `error`, `fatal`, `panic`) |
| `gitlab_runner_log_format` | `runner` | Log format (`runner`, `text`, `json`) |

---

## TLS & Self-Signed Certificate Handling

When `gitlab_url` starts with `https://`:
1. The role extracts the server hostname/IP (`_gitlab_host`).
2. It queries `_gitlab_host:443` via `openssl s_client` and saves the server's PEM certificate into:
   ```text
   /etc/gitlab-runner/certs/{{ _gitlab_host }}.crt
   ```
3. Because `/etc/gitlab-runner` is mounted into the container at `/etc/gitlab-runner`, the certificate is visible inside the container at `/etc/gitlab-runner/certs/{{ _gitlab_host }}.crt`.
4. During registration, the role supplies:
   ```bash
   --tls-ca-file "/etc/gitlab-runner/certs/{{ _gitlab_host }}.crt"
   ```
5. **Subject Alternative Name (SAN) Requirement**: Go 1.17+ strictly enforces SAN validation and rejects certificates that only contain legacy Common Name (`CN`) fields. Ensure the GitLab server's certificate was generated with `-addext "subjectAltName = IP:..., DNS:..."` (as configured by `ro_gitlab_present`).

---

## Example Playbooks

### Standard Deployment (Shell Executor)

```yaml
---
- name: "Deploy GitLab Runner (Podman)"
  hosts: gitlab-runner
  become: true
  vars_files:
    - ./credentials.yml
  tasks:
    - name: "Include ro_gitlab_runner role"
      ansible.builtin.include_role:
        name: ro_gitlab_runner
      vars:
        gitlab_url: "https://192.168.1.129"
        gitlab_runner_registration_token: "{{ runner_registration_token }}"
        gitlab_runner_name: "ubuntu-podman-runner"
        gitlab_runner_tags: "podman,linux"
        gitlab_runner_concurrent: 4
        gitlab_runner_executor: "shell"
```

### Docker Executor via Podman Socket

```yaml
---
- name: "Deploy GitLab Runner (Docker Executor with Podman Socket)"
  hosts: gitlab-runner
  become: true
  vars_files:
    - ./credentials.yml
  tasks:
    - name: "Include ro_gitlab_runner role"
      ansible.builtin.include_role:
        name: ro_gitlab_runner
      vars:
        gitlab_url: "https://192.168.1.129"
        gitlab_runner_registration_token: "{{ runner_registration_token }}"
        gitlab_runner_executor: "docker"
        gitlab_runner_default_image: "alpine:latest"
        gitlab_runner_enable_podman_socket: true
        gitlab_runner_privileged: false
        gitlab_runner_container_env:
          - "DOCKER_HOST=unix:///run/podman/podman.sock"
```

---

## Role Structure

```text
ro_gitlab_runner/
├── defaults/
│   └── main.yml                  # Configurable role parameters and defaults
├── vars/
│   ├── main.yml                  # Internal paths and variables
│   ├── RedHat.yml                # RHEL 9 package definitions & SELinux settings
│   └── Debian.yml                # Ubuntu/Debian package definitions & AppArmor settings
├── tasks/
│   ├── main.yml                  # Role orchestrator and execution entry point
│   ├── assert.yml                # Variable assertions and sanity checks
│   ├── install_podman_redhat.yml # RHEL Podman and SELinux setup
│   ├── install_podman_debian.yml # Debian/Ubuntu Podman and AppArmor setup
│   ├── configure.yml             # Directories, TLS certificate fetching, config.toml render
│   ├── container.yml             # Image pull, volume assembly, container lifecycle
│   ├── register.yml              # Idempotent runner registration with GitLab server
│   └── systemd.yml               # Systemd unit generation (`podman generate systemd --new`)
├── templates/
│   └── config.toml.j2            # GitLab Runner initial configuration template
├── handlers/
│   └── main.yml                  # Container restart handlers
├── meta/
│   └── main.yml                  # Galaxy metadata and platform support
└── tests/
    ├── inventory                 # Local testing inventory
    └── test.yml                  # Test execution playbook
```

---

## Idempotency Notes

| Operation | How Idempotency Is Achieved |
| :--- | :--- |
| **Package Installation** | Uses `state: present` via APT / DNF modules |
| **Directory Creation** | `ansible.builtin.file` with `state: directory` |
| **TLS Certificate Fetch** | Certificate is updated dynamically using `openssl s_client` |
| **Config File** | Rendered on initial deployment; skipped if `config.toml` already exists on disk |
| **Container Lifecycle** | Managed by `containers.podman.podman_container` (re-created only on digest change) |
| **Registration** | Inspects `config.toml` for existing `token = "..."` using safe regex guards (`\| default([], true)`); skips registration if already registered |
| **Systemd Service** | Managed via `podman generate systemd --new --replace` and `ansible.builtin.systemd` |

---

## Security Considerations

- **Secrets Handling**: Registration tokens and authentication tokens are masked with `no_log: true` on sensitive Ansible tasks.
- **Vault Encryption**: Always store `gitlab_runner_registration_token` and `ansible_user_password` in an **Ansible Vault** file (`credentials.yml`).
- **SELinux & AppArmor**: The role automatically configures SELinux container cgroups on RHEL and activates AppArmor on Debian/Ubuntu.
- **Volume Separation**: Container volumes (`gitlab_runner_extra_volumes`) are strictly decoupled from CI job executor volumes (`gitlab_runner_volumes`) to prevent mount collision.

---

## Decommissioning Counterpart

To cleanly unregister and decommission this runner, use the companion teardown role:
- Role: [`ro_gitlab_runner_absent`](../ro_gitlab_runner_absent)
- Playbook: [`pb_gitlab_runner_absent.yml`](../../pb_gitlab_runner_absent.yml)

---

## License

MIT-0

## Author Information

Part of the gitlab-ansible automation project.
