# GitLab Ansible Automation

Ansible playbooks and roles designed to automate the installation, configuration, and provisioning of a **GitLab Server** (GitLab CE) and **GitLab Runners** on Enterprise Linux (RHEL 9 / 10) and other Linux distributions.

---

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quickstart](#quickstart)
  - [1. Inventory Configuration](#1-inventory-configuration)
  - [2. Credentials Setup](#2-credentials-setup)
  - [3. Running the Playbook](#3-running-the-playbook)
- [Playbooks](#playbooks)
- [Role: `ro_gitlab_present`](#role-ro_gitlab_present)
- [Role: `ro_gitlab_runner`](#role-ro_gitlab_runner)
- [Documentation](#documentation)
- [Development Environment](#development-environment)
- [License](#license)

---

## Overview

This repository provides an automated workflow to deploy and configure GitLab CE and GitLab Runners on **RHEL 9** and **Ubuntu Noble (24.04)** hosts using Ansible. Both roles auto-detect the target OS and apply the correct packages, firewall rules, and security policies.

### Key Capabilities

- **Cross-Platform**: All roles auto-detect the target OS (`ansible_os_family`) and dispatch to OS-specific task files — RHEL uses `dnf`/`firewalld`/SELinux, Ubuntu uses `apt`/`ufw`/AppArmor.
- **Host Preparation**: Installs required dependencies and configures firewall rules for HTTP/HTTPS on both RHEL (`firewalld`) and Ubuntu (`ufw`).
- **GitLab Installation**: Adds the official GitLab repository for the target OS and installs GitLab CE/EE via the native package manager.
- **SSL/TLS**: Generates self-signed certificates or deploys user-provided certs. Configurable via `gls_ssl_enabled` and `gls_ssl_self_signed`.
- **Service Configuration**: Renders `gitlab.rb` configuration, manages GitLab licensing, triggers `gitlab-ctl reconfigure`, and validates service health through readiness endpoints.
- **Post-Install Customization**: Uses `gitlab-rails runner` with custom Ruby scripts to automate post-installation settings.
- **GitLab Runner (Podman)**: Installs Podman on the target VM, pulls the GitLab Runner container image, registers the runner, and wires it to systemd — with SELinux policies on RHEL and AppArmor on Ubuntu.
- **Molecule Testing**: Both roles include Molecule scenarios that test against RHEL 9 and Ubuntu Noble containers.
- **Containerized Dev Environment**: Includes a VS Code Dev Container configured with the official Ansible Execution Environment.

---

## Repository Structure

```text
gitlab-ansible/
├── LICENSE                          # MIT License
├── README.md                        # Project documentation (this file)
├── docs/
│   └── WALKTHROUGH_gitlab_runner.md # Step-by-step runner deployment guide
└── gitlab/
    ├── .devcontainer/               # Dev container setup (Dockerfile & devcontainer.json)
    ├── inventory/
    │   └── hosts.yml                # Host inventory and connection details
    ├── credentials.yml              # Ansible Vault encrypted secrets
    ├── pb_gitlab_present.yml        # Playbook: deploy GitLab CE server
    ├── pb_gitlab_runner.yml         # Playbook: deploy GitLab Runner (Podman)
    ├── pb_get_hostname.yml          # Diagnostic playbook to test connectivity
    ├── pb_test_ansible_dev_env.yml  # Environment validation playbook
    └── roles/
        ├── ro_gitlab_present/       # Role: GitLab CE server lifecycle
        │   ├── defaults/main.yml    # Configurable variables (SSL, LDAP, DB, etc.)
        │   ├── vars/                # OS-specific vars
        │   │   ├── main.yml         # Shared internal variables
        │   │   ├── RedHat.yml       # RHEL packages, firewalld
        │   │   └── Debian.yml       # Ubuntu packages, ufw
        │   ├── tasks/               # OS-dispatched task phases
        │   │   ├── main.yml         # Entry point (OS auto-detection)
        │   │   ├── assert.yml       # Pre-flight validation
        │   │   ├── prepare_redhat.yml
        │   │   ├── prepare_debian.yml
        │   │   ├── install_redhat.yml
        │   │   ├── install_debian.yml
        │   │   ├── ssl.yml          # Self-signed or user-provided certs
        │   │   ├── configure.yml    # gitlab.rb render + reconfigure
        │   │   ├── gitlab_ruby_configuration.yml
        │   │   └── cleanup.yml
        │   ├── templates/           # gitlab.rb.j2, Ruby scripts
        │   ├── handlers/main.yml    # Reconfigure, restart, firewall reload
        │   ├── molecule/default/    # Molecule test scenarios (RHEL 9 + Ubuntu)
        │   └── files/               # Static assets (favicons, logos)
        └── ro_gitlab_runner/        # Role: GitLab Runner via Podman
            ├── defaults/main.yml    # All user-configurable variables
            ├── vars/                # OS-specific vars
            │   ├── main.yml         # Shared internal variables
            │   ├── RedHat.yml       # RHEL Podman packages, SELinux
            │   └── Debian.yml       # Ubuntu Podman packages, AppArmor
            ├── tasks/               # OS-dispatched task phases
            │   ├── main.yml         # Entry point (OS auto-detection)
            │   ├── assert.yml
            │   ├── install_podman_redhat.yml
            │   ├── install_podman_debian.yml
            │   ├── configure.yml
            │   ├── container.yml
            │   ├── register.yml
            │   └── systemd.yml
            ├── templates/config.toml.j2
            ├── handlers/main.yml
            ├── molecule/default/    # Molecule test scenarios (RHEL 9 + Ubuntu)
            └── tests/
```

---

## Prerequisites

- **Control Node**:
  - Ansible 2.14+ (or use the included [Dev Container](#development-environment))
  - Python 3.9+
  - SSH key or password-based authentication (`sshpass` if using passwords)
  - Ansible collections (install before first use):
    ```bash
    ansible-galaxy collection install containers.podman community.general community.crypto ansible.posix
    ```
- **Target Host (GitLab Server or Runner)**:
  - **RHEL 9** / Rocky / AlmaLinux 9, or **Ubuntu Noble (24.04)** / Debian 12
  - Sudo/root access (`ansible_become: true`)
  - Internet access (to add GitLab repo and pull container images)
  - For GitLab Server: 4+ CPU cores, 4 GB+ RAM recommended
  - For GitLab Runner: 2+ CPU cores, 2 GB+ RAM (scale with `gitlab_runner_concurrent`)


---

## Quickstart

### 1. Inventory Configuration

Define your target server in `gitlab/inventory/hosts.yml`:

```yaml
all:
  hosts:
    gitlab_server:
      ansible_host: 192.168.1.135
      ansible_user: root
      ansible_password: "{{ gitlab_host_password }}"
```

### 2. Credentials Setup

Sensitive variables (such as SSH passwords, admin credentials, or tokens) are managed with Ansible Vault:

```bash
cd gitlab
ansible-vault create credentials.yml
# Or edit existing vault file:
ansible-vault edit credentials.yml
```

### 3. Running the Playbook

Execute the deployment playbook targeting your host:

```bash
cd gitlab
ansible-playbook pb_gitlab_present.yml \
  -i inventory/hosts.yml \
  --extra-vars "ip_address_v4=192.168.1.135"
```

---

## Playbooks

| Playbook | Description |
|---|---|
| [`pb_gitlab_present.yml`](gitlab/pb_gitlab_present.yml) | Deploy and configure a GitLab CE server (invokes `ro_gitlab_present`). |
| [`pb_gitlab_absent.yml`](gitlab/pb_gitlab_absent.yml) | Remove GitLab CE/EE from a server (invokes `ro_gitlab_absent`). |
| [`pb_gitlab_runner.yml`](gitlab/pb_gitlab_runner.yml) | Deploy a GitLab Runner as a Podman container (invokes `ro_gitlab_runner`). |
| [`pb_get_hostname.yml`](gitlab/pb_get_hostname.yml) | Quick connectivity and OS verification playbook. |
| [`pb_test_ansible_dev_env.yml`](gitlab/pb_test_ansible_dev_env.yml) | Validates local Ansible version, Python interpreter, OS environment, and write permissions. |

---

## Role: `ro_gitlab_present`

Install and configure **GitLab CE/EE** on RHEL 9 or Ubuntu Noble. The role auto-detects the target OS and dispatches to OS-specific task files.

| Supported OS | Package manager | Firewall | Security |
|---|---|---|---|
| RHEL 9 / Rocky / AlmaLinux 9 | `dnf` | `firewalld` | SELinux |
| Ubuntu Noble 24.04 / Debian 12 | `apt` | `ufw` | AppArmor |

The role is divided into structured task phases:

1. **`assert.yml`**: Validates that `gls_domain`, `gls_external_url`, and `gls_admin_password` are set.
2. **`prepare_redhat.yml` / `prepare_debian.yml`**: Installs OS-specific dependencies, configures firewall rules, and starts required services.
3. **`install_redhat.yml` / `install_debian.yml`**: Adds the official GitLab repository and installs the package via the native package manager. Idempotent — skips if already installed.
4. **`ssl.yml`**: Creates the SSL directory; generates a self-signed certificate (using `community.crypto`) or copies user-provided certs. Controlled by `gls_ssl_enabled` and `gls_ssl_self_signed`.
5. **`configure.yml`**: Renders `gitlab.rb.j2`, copies the license file, flushes the `Reconfigure GitLab` handler, and waits for the readiness endpoint.
6. **`gitlab_ruby_configuration.yml`**: Runs `rails_configuration_steps.rb` through `gitlab-rails runner` for initial account setup.
7. **`cleanup.yml`**: Removes temporary installation artifacts.

Key role configuration defaults can be viewed and overridden in [`roles/ro_gitlab_present/defaults/main.yml`](gitlab/roles/ro_gitlab_present/defaults/main.yml). Full variable documentation is in [`roles/ro_gitlab_present/README.md`](gitlab/roles/ro_gitlab_present/README.md).


---

## Role: `ro_gitlab_absent`

Completely removes a GitLab CE/EE installation. Auto-detects the target OS and uses the correct package manager and firewall tool.

| Phase | Task file | What it does |
|---|---|---|
| 1 | `stop.yml` | `gitlab-ctl stop` → disable `gitlab-runsvdir` → `gitlab-ctl kill` |
| 2 | `uninstall_redhat.yml` / `uninstall_debian.yml` | Remove the package and the GitLab repo |
| 3 | `firewall.yml` | Close HTTP/HTTPS ports (`firewalld` on RHEL, `ufw` on Ubuntu) |
| 4 | `cleanup.yml` | Remove data dirs, SSL certs, system users, leftover systemd units |

All cleanup steps are toggleable — see [`roles/ro_gitlab_absent/defaults/main.yml`](gitlab/roles/ro_gitlab_absent/defaults/main.yml) for the full variable list. The role is idempotent: if GitLab is not installed, it detects this and skips all removal tasks.

---

## Role: `ro_gitlab_runner`

Install and configure a GitLab Runner running inside a **Podman** container, with systemd integration for boot persistence. The role is fully idempotent and supports RHEL, Ubuntu, Debian, and openSUSE.

The role is divided into six task phases:

1. **`assert.yml`**: Validates required variables before any system change is made.
2. **`install_podman_redhat.yml` / `install_podman_debian.yml`**: Installs Podman and dependencies via native package manager (`dnf` / `apt`), configures SELinux booleans on RHEL (`container_manage_cgroup`) or AppArmor on Ubuntu, and activates `podman.socket`.
3. **`configure.yml`**: Creates host directories for config, builds, and cache. Renders `config.toml` from a Jinja2 template on first run only.
4. **`container.yml`**: Pulls the runner OCI image and creates/starts the Podman container. Automatically recreates the container when the image digest changes.
5. **`register.yml`**: Registers the runner with GitLab using `gitlab-runner register`. Parses the existing `config.toml` first — skips registration if a token is already present (preventing duplicate runners).
6. **`systemd.yml`**: Generates a systemd unit file via `podman generate systemd` and enables the service for automatic startup after reboots.

Key role configuration defaults can be viewed and overridden in [`roles/ro_gitlab_runner/defaults/main.yml`](gitlab/roles/ro_gitlab_runner/defaults/main.yml).

For a complete deployment walkthrough, see [docs/WALKTHROUGH_gitlab_runner.md](docs/WALKTHROUGH_gitlab_runner.md).

### Quick deploy

```bash
# 1. Install required collections
ansible-galaxy collection install containers.podman community.general ansible.posix

# 2. Encrypt your runner registration token
ansible-vault encrypt_string 'glrt-xxxxxxxxxxxx' \
  --name 'runner_registration_token' >> gitlab/credentials.yml

# 3. Add runner hosts to inventory, then deploy
ansible-playbook gitlab/pb_gitlab_runner.yml \
  -i gitlab/inventory/hosts.yml \
  -l runner_hosts \
  -e "gitlab_url=https://gitlab.example.com" \
  --ask-vault-pass
```

### OS compatibility

| OS Family | Package Manager | Podman packages |
|---|---|---|
| RHEL / Rocky / AlmaLinux 9–10 | `dnf` | `podman`, `podman-plugins`, `slirp4netns`, `fuse-overlayfs` |
| Ubuntu 22.04 / 24.04, Debian 12 | `apt` | `podman`, `uidmap`, `slirp4netns`, `fuse-overlayfs` |
| openSUSE / SLES | `zypper` | `podman` |

---

## Documentation

| Document | Description |
|---|---|
| [`docs/WALKTHROUGH_gitlab_runner.md`](docs/WALKTHROUGH_gitlab_runner.md) | End-to-end step-by-step guide: prerequisites → inventory → vault → deploy → verify → day-2 ops and troubleshooting. |
| [`roles/ro_gitlab_runner/README.md`](gitlab/roles/ro_gitlab_runner/README.md) | Full variable reference, executor examples, idempotency notes, and security guidance for the runner role. |
| [`roles/ro_gitlab_present/README.md`](gitlab/roles/ro_gitlab_present/README.md) | Variable reference for the GitLab server role. |

---

## Development Environment

A ready-to-use development environment is provided via `.devcontainer`:

- Based on `quay.io/ansible/creator-ee:latest`.
- Pre-installed CLI utilities: `tmux`, `vim`, `tree`, `sshpass`.
- Pre-configured VS Code extensions: `redhat.ansible`, `ms-python.python`, `even-better-toml`.
- Pre-configured `ansible.cfg` with disabled host key checking for fast lab iteration.

Open the project folder in VS Code and select **Reopen in Container** when prompted.

---


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
