# GitLab & GitLab Runner Ansible Automation

Ansible playbooks and roles to provision, configure, and decommission a self-hosted **GitLab Server (Omnibus)** and **GitLab Runner (Podman Container)** on Debian/Ubuntu and RedHat/Rocky Linux systems.

## Inventory Architecture

| Host Alias | IP Address | Role | Description |
| :--- | :--- | :--- | :--- |
| `gitlab-server` | `192.168.1.129` | Server | GitLab CE Omnibus instance with PostgreSQL, Redis, Puma, Nginx |
| `gitlab-runner` | `192.168.1.130` | Runner | Containerized GitLab Runner running under Podman and managed by Systemd |

---

## Quickstart

### 1. GitLab Server Deployment
Deploy and configure GitLab Server (including SSL/TLS, database setup, and administrator configuration):

```bash
ansible-playbook pb_gitlab_present.yml -i inventory/hosts.yml
```

### 2. GitLab Runner Deployment
Deploy and register the GitLab Runner with the GitLab Server:

```bash
ansible-playbook pb_gitlab_runner.yml -i inventory/hosts.yml
```

---

## Admin Credentials & Web Access

- **Web UI**: [https://192.168.1.129](https://192.168.1.129) *(accept self-signed TLS certificate warning in browser)*
- **Username**: `gls_admin`
- **Password**: `gls_initial_adm_pwd`

---

## Decommissioning

### Decommission GitLab Runner
Unregisters all runner tokens from the GitLab server, stops and removes the Podman container, cleans systemd units, removes cache/builds/config, and optionally uninstalls Podman:

```bash
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml
```

### Decommission GitLab Server
Stops all GitLab Omnibus services, purges packages, removes repository files, and wipes data directories (`/etc/gitlab`, `/var/opt/gitlab`, `/var/log/gitlab`):

```bash
ansible-playbook pb_gitlab_absent.yml -i inventory/hosts.yml
```

---

## Playbooks & Roles Reference

| Playbook | Roles Included | Purpose |
| :--- | :--- | :--- |
| `pb_gitlab_present.yml` | `ro_gitlab_present` | Installs and configures GitLab Server Omnibus |
| `pb_gitlab_absent.yml` | `ro_gitlab_absent` | Decommissions GitLab Server and wipes data |
| `pb_gitlab_runner.yml` | `ro_gitlab_runner` | Installs Podman, runs runner container, trusts TLS, registers runner |
| `pb_gitlab_runner_absent.yml` | `ro_gitlab_runner_absent` | Unregisters runner, stops container, cleans directories |
