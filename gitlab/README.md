# GitLab & GitLab Runner Ansible Automation

Production-ready Ansible playbooks and modular roles to deploy, configure, verify, and decommission a self-hosted **GitLab CE Server (Omnibus)** and containerized **GitLab Runner (Podman)** on Ubuntu Noble (24.04) and RHEL 9 / Rocky Linux 9 systems.

---

## Architecture & Topology

```mermaid
flowchart TD
    subgraph ControlNode["Ansible Control Node"]
        A["Ansible Core >= 2.14"]
        INV["inventory/hosts.yml"]
        SEC["credentials.yml (Vault)"]
    end

    subgraph ServerNode["GitLab Server (192.168.1.129)"]
        NGINX["Nginx HTTPS (:443)"]
        SAN["TLS Certificate with SAN"]
        PUMA["Puma Web Application Server"]
        PG["PostgreSQL (Internal)"]
        REDIS["Redis (Internal)"]
        RUNSV["gitlab-runsvdir (Systemd)"]
    end

    subgraph RunnerNode["GitLab Runner Node (192.168.1.130)"]
        SVC["Systemd: container-gitlab-runner.service"]
        PODMAN["Podman Engine (v4.9.3)"]
        RUNNER["Container: gitlab/gitlab-runner:latest"]
        CA["Trusted Server CA (/etc/gitlab-runner/certs)"]
    end

    ControlNode -->|SSH :22| ServerNode
    ControlNode -->|SSH :22| RunnerNode
    RUNNER -->|HTTPS :443 (Verified via Server CA)| NGINX
```

### Managed Nodes

| Host Alias | IP Address | OS / Platform | Component | Description |
| :--- | :--- | :--- | :--- | :--- |
| `gitlab-server` | `192.168.1.129` | Ubuntu 24.04 (Noble) | GitLab CE Omnibus | Central repository server, web UI, API, PostgreSQL, Redis, Puma |
| `gitlab-runner` | `192.168.1.130` | Ubuntu 24.04 (Noble) | GitLab Runner (Podman) | Containerized CI/CD build worker managed via systemd |

---

## Requirements

### Control Node
- **Ansible**: `>= 2.14`
- **Collections**:
  - `containers.podman`
  - `ansible.posix`
  - `ansible.builtin`
- **Ansible Vault Password**: Configured globally in `/etc/ansible/ansible.cfg` (`vault_password_file = /etc/ansible/vaultpass.txt`) or passed via `--ask-vault-pass`.

### Inventory Setup (`inventory/hosts.yml`)
```yaml
all:
  hosts:
    gitlab-server:
      ansible_host: 192.168.1.129
      ansible_user: jono
      ansible_password: "{{ ansible_user_password }}"
    gitlab-runner:
      ansible_host: 192.168.1.130
      ansible_user: jono
      ansible_password: "{{ ansible_user_password }}"
```

---

## 1. Installing GitLab Server

The [`pb_gitlab_present.yml`](pb_gitlab_present.yml) playbook provisions the target host with the official GitLab CE Omnibus package, configures self-signed TLS with Subject Alternative Names (SAN), initializes services via Runit and Systemd, converges Omnibus configuration, and sets up administrator credentials.

### Execution

```bash
ansible-playbook pb_gitlab_present.yml -i inventory/hosts.yml
```

### Custom Variables (Optional Overrides)

```bash
# Override domain/IP or admin password
ansible-playbook pb_gitlab_present.yml -i inventory/hosts.yml \
  -e "gls_domain=gitlab.example.com" \
  -e "gls_admin_password=CustomSecurePassword123!"
```

### Verification & Web Access

Once the playbook finishes:
1. **Web Interface**: Open [https://192.168.1.129](https://192.168.1.129) *(accept browser TLS warning for self-signed certificate)*
2. **Initial Administrator Credentials**:
   - **Username**: `gls_admin` (or email: `gitlab_admin_1320ee@example.com`)
   - **Password**: `gls_initial_adm_pwd`
3. **Health Check Endpoint**:
   ```bash
   curl -k -i https://192.168.1.129/-/readiness
   ```
4. **Service Status via CLI**:
   ```bash
   ansible gitlab-server -i inventory/hosts.yml -e @credentials.yml -b -m command -a "gitlab-ctl status"
   ```

---

## 2. Installing GitLab Runner

The [`pb_gitlab_runner.yml`](pb_gitlab_runner.yml) playbook provisions Podman on the runner host, fetches the GitLab server's TLS certificate into `/etc/gitlab-runner/certs/`, pulls the official runner container image, starts the container with isolated bind mounts, registers the runner against GitLab, and creates a systemd service (`container-gitlab-runner.service`).

### Execution

```bash
ansible-playbook pb_gitlab_runner.yml -i inventory/hosts.yml
```

### Custom Variables (Optional Overrides)

```bash
# Configure Docker executor and custom job tags
ansible-playbook pb_gitlab_runner.yml -i inventory/hosts.yml \
  -e "gitlab_runner_executor=docker" \
  -e "gitlab_runner_tags=docker,linux" \
  -e "gitlab_runner_concurrent=8"
```

### Verification

1. **Systemd Service State**:
   ```bash
   ansible gitlab-runner -i inventory/hosts.yml -e @credentials.yml -b -m command \
     -a "systemctl status container-gitlab-runner"
   ```
2. **GitLab REST API Verification** (confirm runner status is `online`):
   ```bash
   curl -k -s -H "PRIVATE-TOKEN: admin_token" https://192.168.1.129/api/v4/runners/all
   ```

---

## 3. Decommissioning GitLab Runner

The [`pb_gitlab_runner_absent.yml`](pb_gitlab_runner_absent.yml) playbook unregisters the runner from the GitLab server, stops and disables the systemd service unit, removes the Podman container and OCI image, and cleans up host configuration and cache directories.

### Standard Decommissioning

```bash
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml
```

### Decommissioning Options

```bash
# Teardown runner but preserve CI cache and build directories
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml \
  -e "glra_remove_data=false"

# Complete host teardown including uninstallation of Podman packages
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml \
  -e "glra_remove_podman=true" \
  -e "glra_remove_podman_socket=true"

# Skip server unregistration (if the GitLab server is already offline or deleted)
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml \
  -e "glra_unregister=false"
```

---

## 4. Decommissioning GitLab Server

The [`pb_gitlab_absent.yml`](pb_gitlab_absent.yml) playbook stops all running GitLab Omnibus services, purges packages via the system package manager (APT/DNF), deletes repository configurations and GPG keys, closes firewall ports, and wipes all application data.

### Standard Decommissioning

```bash
ansible-playbook pb_gitlab_absent.yml -i inventory/hosts.yml
```

### Decommissioning Options

```bash
# Remove software but preserve repositories, database, and config directories
ansible-playbook pb_gitlab_absent.yml -i inventory/hosts.yml \
  -e "gla_remove_data=false"

# Purge software, data, and remove GitLab system users (git, gitlab-www)
ansible-playbook pb_gitlab_absent.yml -i inventory/hosts.yml \
  -e "gla_remove_users=true"
```

---

## Complete Lifecycle Playbook Reference

| Lifecycle Phase | Playbook | Target Host | Included Role | Primary Actions |
| :--- | :--- | :--- | :--- | :--- |
| **Server Install** | [`pb_gitlab_present.yml`](pb_gitlab_present.yml) | `gitlab-server` | [`ro_gitlab_present`](roles/ro_gitlab_present) | Installs `gitlab-ce`, generates SAN cert, configures `gitlab.rb`, seeds admin |
| **Runner Install** | [`pb_gitlab_runner.yml`](pb_gitlab_runner.yml) | `gitlab-runner` | [`ro_gitlab_runner`](roles/ro_gitlab_runner) | Installs Podman, trusts TLS cert, runs container, registers runner, enables systemd |
| **Runner Teardown** | [`pb_gitlab_runner_absent.yml`](pb_gitlab_runner_absent.yml) | `gitlab-runner` | [`ro_gitlab_runner_absent`](roles/ro_gitlab_runner_absent) | Unregisters runner from GitLab, stops systemd unit, removes container & data |
| **Server Teardown** | [`pb_gitlab_absent.yml`](pb_gitlab_absent.yml) | `gitlab-server` | [`ro_gitlab_absent`](roles/ro_gitlab_absent) | Stops omnibus services, purges packages, removes repos, wipes `/var/opt/gitlab` |

---

## Documentation Links

- **End-to-End Walkthrough & Troubleshooting**: [`WALKTHROUGH.md`](WALKTHROUGH.md)
- **GitLab Server Role**: [`roles/ro_gitlab_present/README.md`](roles/ro_gitlab_present/README.md)
- **GitLab Server Absent Role**: [`roles/ro_gitlab_absent/README.md`](roles/ro_gitlab_absent/README.md)
- **GitLab Runner Role**: [`roles/ro_gitlab_runner/README.md`](roles/ro_gitlab_runner/README.md)
- **GitLab Runner Absent Role**: [`roles/ro_gitlab_runner_absent/README.md`](roles/ro_gitlab_runner_absent/README.md)
