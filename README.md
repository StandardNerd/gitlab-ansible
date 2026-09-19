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

This repository provides an automated workflow to deploy and configure GitLab CE on RHEL-based hosts using Ansible.

### Key Capabilities

- **Host Preparation**: Automatically verifies DNF release version, installs required dependencies (`python3-libdnf`, `curl`, `postfix`, `firewalld`, `postgresql`, etc.), and configures firewall rules for HTTP/HTTPS.
- **GitLab Installation**: Checks package facts and installs GitLab CE directly via DNF.
- **Service Configuration**: Renders `gitlab.rb` configuration, manages GitLab licensing, triggers `gitlab-ctl reconfigure` asynchronously, and validates service health through readiness endpoints (`/-/readiness`).
- **Post-Install Customization**: Uses `gitlab-rails runner` with custom Ruby scripts to automate post-installation settings, such as administrative access token creation and branding assets.
- **GitLab Runner (Podman)**: Installs Podman on the target VM, pulls the GitLab Runner container image, registers the runner with your GitLab instance, and wires it to systemd for boot persistence — all idempotently.
- **Containerized Dev Environment**: Includes a VS Code Dev Container configured with the official Ansible Execution Environment (`quay.io/ansible/creator-ee:latest`).

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
        │   ├── defaults/            # Default variables (ports, URLs, LDAP config)
        │   ├── files/               # Static assets (favicons, logos)
        │   ├── tasks/               # Execution phases (prepare, install, reconfigure, etc.)
        │   └── templates/           # Jinja2 templates (gitlab.rb.j2, Ruby scripts)
        └── ro_gitlab_runner/        # Role: GitLab Runner via Podman
            ├── defaults/            # All user-configurable variables
            ├── vars/                # Internal role variables (OS package maps, paths)
            ├── tasks/               # Phases: assert, install, configure, container, register, systemd
            ├── templates/           # config.toml.j2
            ├── handlers/            # Container restart & systemd reload
            ├── meta/                # Galaxy metadata and platform matrix
            └── tests/               # Smoke-test playbook and inventory
```

---

## Prerequisites

- **Control Node**:
  - Ansible 2.14+ (or use the included [Dev Container](#development-environment))
  - Python 3.9+
  - SSH key or password-based authentication (`sshpass` if using passwords)
  - Ansible collections: `containers.podman`, `community.general`, `ansible.posix` (required by `ro_gitlab_runner`)
    ```bash
    ansible-galaxy collection install containers.podman community.general ansible.posix
    ```
- **Target Host (GitLab Server)**:
  - RHEL 9 / 10 or compatible Enterprise Linux distribution
  - Sudo/root access (`ansible_become: true`)
  - Minimum hardware requirements for GitLab (recommended: 4+ CPU cores, 4GB+ RAM)
- **Target Host (GitLab Runner)**:
  - RHEL 9/10, Ubuntu 22.04/24.04, Debian 12, or openSUSE/SLES
  - Sudo/root access (`ansible_become: true`)
  - Outbound network access to your GitLab instance and to `docker.io` (to pull the runner image)
  - Minimum: 2 CPU cores, 2GB RAM (scale with `gitlab_runner_concurrent`)

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
| [`pb_gitlab_present.yml`](gitlab/pb_gitlab_present.yml) | Main playbook that invokes `ro_gitlab_present` to deploy and configure GitLab. |
| [`pb_get_hostname.yml`](gitlab/pb_get_hostname.yml) | Quick connectivity verification playbook to test host access and reachability. |
| [`pb_test_ansible_dev_env.yml`](gitlab/pb_test_ansible_dev_env.yml) | Validates local Ansible version, Python interpreter, OS environment, and write permissions. |

---

## Role: `ro_gitlab_present`

The main role is divided into structured task stages:

1. **`prepare.yml`**: Verifies system prerequisites, installs system packages, enables and opens ports in `firewalld`.
2. **`install.yml`**: Verifies if GitLab is already present; if not, installs the specified RPM/package via DNF.
3. **`gitlab_base_configuration.yml` / `reconfigure.yml`**: Deploys `gitlab.rb.j2`, handles licensing, triggers `gitlab-ctl reconfigure`, and polls the readiness endpoint (`/-/readiness`).
4. **`gitlab_ruby_configuration.yml`**: Runs `rails_configuration_steps.rb` through `gitlab-rails runner` for initial account setup and customization.
5. **`cleanup.yml`**: Cleans up temporary installation artifacts.

Key role configuration defaults can be viewed and overridden in [`roles/ro_gitlab_present/defaults/main.yml`](gitlab/roles/ro_gitlab_present/defaults/main.yml).

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
