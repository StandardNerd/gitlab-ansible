# GitLab & GitLab Runner Infrastructure Walkthrough

This document provides a comprehensive end-to-end guide to the deployment, architecture, verification, troubleshooting, and decommissioning of the GitLab Server and GitLab Runner infrastructure managed via Ansible.

---

## 1. System Architecture & Topology

The deployment consists of two dedicated nodes orchestrated by Ansible from the control host:

```mermaid
flowchart TD
    subgraph ControlHost["Ansible Control Host (Mac)"]
        A["Ansible Core 2.20"]
        V["/etc/ansible/vaultpass.txt"]
        C["credentials.yml (Vault)"]
        I["inventory/hosts.yml"]
    end

    subgraph ServerNode["GitLab Server (192.168.1.129)"]
        S_NGINX["Nginx (HTTPS :443)"]
        S_TLS["Self-Signed Cert with SAN"]
        S_PUMA["Puma Web Application Server"]
        S_PG["PostgreSQL (Internal)"]
        S_REDIS["Redis (Internal)"]
        S_RUNSV["GitLab Runsvdir (Systemd)"]
    end

    subgraph RunnerNode["GitLab Runner Node (192.168.1.130)"]
        R_SYS["Systemd: container-gitlab-runner.service"]
        R_PODMAN["Podman Runtime (v4.9.3)"]
        R_CTR["Container: gitlab-runner:latest"]
        R_VOL_CFG["/etc/gitlab-runner/config.toml"]
        R_VOL_CA["/etc/gitlab-runner/certs/192.168.1.129.crt"]
        R_VOL_CACHE["/var/lib/gitlab-runner/cache"]
        R_VOL_BUILDS["/var/lib/gitlab-runner/builds"]
    end

    ControlHost -->|SSH port 22| ServerNode
    ControlHost -->|SSH port 22| RunnerNode
    R_CTR -->|HTTPS :443 (TLS verified via SAN CA)| S_NGINX
```

### Node Specifications

| Node | IP Address | OS / Kernel | Software Stack | Role / Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `gitlab-server` | `192.168.1.129` | Ubuntu 24.04 (Noble) | GitLab CE Omnibus 17.x, OpenSSL 3.0 | Central GitLab instance |
| `gitlab-runner` | `192.168.1.130` | Ubuntu 24.04 (Noble) | Podman 4.9.3, Systemd, `gitlab-runner:latest` | CI/CD build worker |

---

## 2. Repository Structure & Roles

```text
gitlab/
├── inventory/
│   └── hosts.yml                      # Target hosts inventory with SSH connection params
├── credentials.yml                    # Ansible Vault credentials (user, password, become)
├── pb_gitlab_present.yml              # Playbook: Deploy GitLab Server
├── pb_gitlab_absent.yml               # Playbook: Decommission GitLab Server
├── pb_gitlab_runner.yml               # Playbook: Deploy GitLab Runner (Podman)
├── pb_gitlab_runner_absent.yml        # Playbook: Decommission GitLab Runner
└── roles/
    ├── ro_gitlab_present/             # GitLab Server installation role
    │   ├── defaults/main.yml          # Role configuration defaults (ports, SSL, LDAP, admin)
    │   ├── tasks/ssl.yml              # TLS cert generation with SAN extensions
    │   ├── tasks/configure.yml        # gitlab.rb rendering, runit service startup
    │   ├── templates/gitlab.rb.j2     # Main GitLab Omnibus configuration template
    │   └── templates/rails_configuration_steps.rb # Idempotent Rails admin seed script
    ├── ro_gitlab_absent/              # GitLab Server purge & cleanup role
    ├── ro_gitlab_runner/              # GitLab Runner container deployment role
    │   ├── defaults/main.yml          # Runner parameters, concurrency, executor mode
    │   ├── tasks/configure.yml        # Directory creation & server CA auto-fetch
    │   ├── tasks/container.yml        # Podman container lifecycle & volume binding
    │   ├── tasks/register.yml         # Non-interactive registration with GitLab server
    │   └── tasks/systemd.yml          # Systemd unit generation & enablement
    └── ro_gitlab_runner_absent/       # GitLab Runner decommissioning role
        ├── defaults/main.yml          # Unregister options, directory cleanup flags
        └── tasks/unregister.yml       # Server unregistration & container removal
```

---

## 3. Step-by-Step Deployment Guide

### Step 1: Pre-Flight Environment Checks

Verify Ansible connectivity and SSH authentication across both nodes:

```bash
# Check basic connectivity and python environment
ansible all -i inventory/hosts.yml -e @credentials.yml -m ping
```

> [!NOTE]
> The Ansible Vault password file is globally configured in `/etc/ansible/ansible.cfg` pointing to `/etc/ansible/vaultpass.txt`. You do not need to supply `--ask-vault-pass` manually.

---

### Step 2: Deploy GitLab Server

Run the server deployment playbook:

```bash
ansible-playbook pb_gitlab_present.yml -i inventory/hosts.yml
```

#### What happens during execution:
1. **OS Preparation**: Installs dependencies (`curl`, `openssh-server`, `ca-certificates`, `tzdata`, `perl`).
2. **Repository Setup**: Adds the official GitLab CE APT repository key and source lists.
3. **Package Installation**: Installs `gitlab-ce`.
4. **TLS Certificate**: Generates a 2048-bit RSA self-signed TLS certificate at `/etc/gitlab/ssl/192.168.1.129.crt` with **Subject Alternative Name (SAN)** extensions (`IP:192.168.1.129, IP:127.0.0.1`).
5. **Configuration**: Renders `/etc/gitlab/gitlab.rb` with custom settings (external URL, disabled sign-ups, LDAP structure, custom branding).
6. **Service Initialization**: Enables and starts `gitlab-runsvdir` under systemd.
7. **Omnibus Reconfigure**: Executes `gitlab-ctl reconfigure` to converge all internal components (PostgreSQL, Redis, Puma, Gitaly, Nginx).
8. **Admin Provisioning**: Runs `rails_configuration_steps.rb` to create or update administrator credentials and security settings idempotently.

---

### Step 3: Verify GitLab Server & Access Web UI

Verify service readiness via HTTP endpoints and CLI:

```bash
# Verify health check endpoint (returns HTTP 200)
curl -k -i https://192.168.1.129/-/readiness

# Check all internal service states
ansible gitlab-server -i inventory/hosts.yml -e @credentials.yml -b -m command -a "gitlab-ctl status"
```

#### Administrator Login Credentials
- **Web URL**: `https://192.168.1.129` *(Bypass browser self-signed TLS warning)*
- **Username**: `gls_admin` (or email: `gitlab_admin_1320ee@example.com`)
- **Password**: `gls_initial_adm_pwd`

---

### Step 4: Deploy GitLab Runner (Podman)

Run the runner deployment playbook:

```bash
ansible-playbook pb_gitlab_runner.yml -i inventory/hosts.yml
```

#### What happens during execution:
1. **Dependency Installation**: Installs `podman`, `podman-docker`, and `apparmor` on `192.168.1.130`. Enables the root Podman socket (`podman.socket`).
2. **Directory Structure**: Creates `/etc/gitlab-runner`, `/etc/gitlab-runner/certs`, `/var/lib/gitlab-runner/builds`, and `/var/lib/gitlab-runner/cache`.
3. **CA Certificate Fetch**: Automatically queries `192.168.1.129:443` via `openssl s_client` and saves the server's public certificate to `/etc/gitlab-runner/certs/192.168.1.129.crt`.
4. **Container Launch**: Pulls `docker.io/gitlab/gitlab-runner:latest` and starts the `gitlab-runner` container with appropriate bind mounts.
5. **Registration**: Invokes `gitlab-runner register` inside the container using the instance registration token (`4gcyYJNxXUxMZKji5WpA`) and the `--tls-ca-file` flag.
6. **Systemd Persistence**: Generates and enables `container-gitlab-runner.service` using `podman generate systemd --new --replace`.

---

### Step 5: Verify GitLab Runner

#### Check Systemd Service Status on the Runner Host:
```bash
ansible gitlab-runner -i inventory/hosts.yml -e @credentials.yml -b -m command \
  -a "systemctl status container-gitlab-runner"
```

Expected output confirms `active (running)`:
```text
● container-gitlab-runner.service - Podman container-gitlab-runner.service
     Loaded: loaded (/etc/systemd/system/container-gitlab-runner.service; enabled; preset: enabled)
     Active: active (running)
```

#### Query Runner Status via GitLab Server REST API:
```bash
curl -k -s -H "PRIVATE-TOKEN: admin_token" https://192.168.1.129/api/v4/runners/all
```

Response confirms `online: true` and status `online`:
```json
[
  {
    "id": 2,
    "description": "gitlab-runner-podman-runner",
    "name": "gitlab-runner",
    "online": true,
    "status": "online",
    "active": true,
    "job_execution_status": "idle"
  }
]
```

---

## 4. Decommissioning Procedures

### Decommission GitLab Runner Only

To remove the GitLab Runner without affecting the GitLab Server:

```bash
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml
```

**Actions performed by `ro_gitlab_runner_absent`**:
- Unregisters all runner instances from GitLab (`podman exec gitlab-runner gitlab-runner unregister --all-runners`).
- Stops and disables `container-gitlab-runner.service`.
- Removes the generated systemd unit file `/etc/systemd/system/container-gitlab-runner.service`.
- Removes the `gitlab-runner` Podman container and deletes the image.
- Purges configuration, cache, and build directories (`/etc/gitlab-runner`, `/var/lib/gitlab-runner`).
- Optionally uninstalls Podman packages (if `glra_uninstall_podman: true`).

---

### Decommission GitLab Server

To completely tear down the GitLab Server and wipe all hosted repositories and database records:

```bash
ansible-playbook pb_gitlab_absent.yml -i inventory/hosts.yml
```

**Actions performed by `ro_gitlab_absent`**:
- Stops all running GitLab services via `gitlab-ctl stop`.
- Stops and disables `gitlab-runsvdir.service`.
- Purges `gitlab-ce` package via APT/DPKG.
- Removes the GitLab package repository configuration and keys from `/etc/apt/sources.list.d/`.
- Deletes all data, configuration, and log directories:
  - `/etc/gitlab`
  - `/var/opt/gitlab`
  - `/var/log/gitlab`
- Cleans up firewall rules.

---

## 5. Troubleshooting & Known Bugs Reference

The table below summarizes key errors encountered and resolved during playbook development:

| Symptom / Error Message | Component | Root Cause | Permanent Resolution |
| :--- | :--- | :--- | :--- |
| `Recursive loop detected in template: maximum recursion depth exceeded` | `pb_gitlab_runner.yml` & `inventory/hosts.yml` | Variables assigned to expressions referencing their own names in the same scope (`gitlab_url: "{{ gitlab_url ... }}"` and `ansible_user: "{{ ansible_user }}"`). | Removed redundant variable in playbook; set explicit `ansible_user: jono` in inventory. |
| `Error: /cache: duplicate mount destination` (exit code 125) | `ro_gitlab_runner/tasks/container.yml` | `_runner_volumes` contained both `gitlab_runner_cache_dir:/cache:Z` and `gitlab_runner_volumes` (`["/cache"]`). | Separated runner container mounts from docker executor mounts using `gitlab_runner_extra_volumes`. |
| `tls: failed to verify certificate: x509: certificate relies on legacy Common Name field, use SANs instead` | `ro_gitlab_present/tasks/ssl.yml` & Go TLS engine | Self-signed certificate was generated with only `-subj .../CN=192.168.1.129` without Subject Alternative Names. Go 1.17+ strictly enforces SAN presence. | Added `-addext "subjectAltName = IP:{{ gls_domain }},IP:127.0.0.1"` to OpenSSL certificate generation task. |
| `'NoneType' object is not iterable` in Jinja2 template filter | `ro_gitlab_runner/tasks/register.yml` | `regex_search(...)` returned `None` when `config.toml` did not yet have a runner token, which was directly passed to `| first`. | Added default list guard before indexing: `regex_search(...) \| default([], true) \| first \| default('')`. |
| Task hang during `meta: flush_handlers` | `ro_gitlab_present/tasks/configure.yml` | Omnibus `gitlab-ctl reconfigure` attempted to communicate with Runit before `gitlab-runsvdir.service` was running. | Started and enabled `gitlab-runsvdir` service before triggering handlers. |
| `IPAddr::InvalidAddressError: invalid address` | `ro_gitlab_present/defaults/main.yml` | `enable_ip_list` had `http://192.168.1.129/24` prepended with protocol. | Stripped protocol, leaving raw CIDR notation `192.168.1.129/24`. |
| `IndexError: string not matched` in `1_settings.rb` | `ro_gitlab_present/templates/gitlab.rb.j2` | LDAP block attributes were unindented outside `main:`. | Corrected YAML indentation under LDAP `main:` provider definition. |
