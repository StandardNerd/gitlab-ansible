# Walkthrough: Deploying a GitLab Runner with Podman using `ro_gitlab_runner`

This guide walks you through every step of deploying a GitLab Runner on a VM using the `ro_gitlab_runner` Ansible role — from setting up your control node to watching your first CI/CD job succeed.

---

## Table of Contents

1. [Overview & Architecture](#1-overview--architecture)
2. [Prerequisites Checklist](#2-prerequisites-checklist)
3. [Step 1 — Install Ansible Collections](#step-1--install-ansible-collections)
4. [Step 2 — Add the Runner Host to Inventory](#step-2--add-the-runner-host-to-inventory)
5. [Step 3 — Obtain a Registration Token from GitLab](#step-3--obtain-a-registration-token-from-gitlab)
6. [Step 4 — Store the Token in Ansible Vault](#step-4--store-the-token-in-ansible-vault)
7. [Step 5 — Configure Role Variables](#step-5--configure-role-variables)
8. [Step 6 — Run the Playbook](#step-6--run-the-playbook)
9. [Step 7 — Verify the Runner in GitLab](#step-7--verify-the-runner-in-gitlab)
10. [Step 8 — Run a Test CI/CD Job](#step-8--run-a-test-cicd-job)
11. [Understanding What the Role Does (Phase by Phase)](#understanding-what-the-role-does-phase-by-phase)
12. [Customisation Examples](#customisation-examples)
13. [Day-2 Operations](#day-2-operations)
14. [Troubleshooting](#troubleshooting)

---

## 1. Overview & Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Control Node (your laptop / dev container)                     │
│                                                                 │
│  ansible-playbook pb_gitlab_runner.yml                          │
│         │                                                       │
│         │  SSH                                                  │
│         ▼                                                       │
│  ┌──────────────────────────────┐                               │
│  │  Target VM  (RHEL / Ubuntu)  │                               │
│  │                              │                               │
│  │  ┌───────────────────────┐   │   HTTPS    ┌──────────────┐  │
│  │  │  Podman               │   │ ─────────► │  GitLab CE   │  │
│  │  │  ┌─────────────────┐  │   │ register   │  (existing)  │  │
│  │  │  │ gitlab-runner   │  │   │ ◄───────── │              │  │
│  │  │  │  (container)    │  │   │   jobs     └──────────────┘  │
│  │  │  └─────────────────┘  │   │                               │
│  │  └───────────────────────┘   │                               │
│  │  systemd unit (auto-start)   │                               │
│  └──────────────────────────────┘                               │
└─────────────────────────────────────────────────────────────────┘
```

The runner container connects **outbound** to GitLab — no inbound firewall ports are needed. It polls GitLab for jobs, executes them, and pushes results back over the same connection.

---

## 2. Prerequisites Checklist

Before you begin, confirm:

| Item | Required? | Notes |
|---|---|---|
| Ansible 2.14+ on control node | ✅ | Or use the included Dev Container |
| Python 3.9+ on control node | ✅ | |
| SSH access to the target VM | ✅ | Key-based or password (`sshpass`) |
| `sudo` / root on target VM | ✅ | `ansible_become: true` |
| Target OS: RHEL 9/10, Ubuntu 22+, or Debian 12 | ✅ | Other distros supported — see OS table |
| A running GitLab instance | ✅ | Any edition; self-hosted or SaaS |
| Network path: target VM → GitLab (HTTPS/443) | ✅ | Runner polls outbound |
| Network path: target VM → docker.io (HTTPS/443) | ✅ | To pull the runner image |

---

## Step 1 — Install Ansible Collections

The role depends on three Ansible collections. Install them on your **control node**:

```bash
ansible-galaxy collection install \
  containers.podman \
  community.general \
  ansible.posix
```

Or, if the project has a `requirements.yml`, add them there:

```yaml
# gitlab/requirements.yml
collections:
  - name: containers.podman
    version: ">=1.10.0"
  - name: community.general
    version: ">=6.0.0"
  - name: ansible.posix
    version: ">=1.5.0"
```

Then install:

```bash
cd gitlab
ansible-galaxy collection install -r requirements.yml
```

---

## Step 2 — Add the Runner Host to Inventory

Open `gitlab/inventory/hosts.yml` (or `gitlab/hosts.yml`) and add a group for your runner VM(s):

```yaml
# gitlab/inventory/hosts.yml
all:
  hosts:
    vm1:                          # existing GitLab server (unchanged)
      ansible_host: 10.10.10.10
      ansible_user: foo
      ansible_password: "{{ password }}"
      ansible_become: true

  children:
    runner_hosts:                 # ← new group for runner VMs
      hosts:
        runner01:
          ansible_host: 10.10.10.20   # IP of your runner VM
          ansible_user: ansible
          ansible_become: true
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
```

> [!TIP]
> You can add multiple runner VMs to `runner_hosts` and the playbook will deploy to all of them in parallel.

---

## Step 3 — Obtain a Registration Token from GitLab

Shared runners (available to all projects) are registered from the **Admin area**:

1. Log in to GitLab as an administrator.
2. Go to **Admin Area** → **CI/CD** → **Runners**.
3. Click **New instance runner** (GitLab 16+) or copy the **Registration token** shown on that page (GitLab 15 and earlier).
4. Copy the token — it looks like `glrt-xxxxxxxxxxxxxxxx`.

For a **project-specific runner**:

1. Open the project → **Settings** → **CI/CD** → **Runners** → **Expand**.
2. Copy the registration token from the "Set up a project runner" section.

---

## Step 4 — Store the Token in Ansible Vault

Never commit tokens in plaintext. Add the token to the **existing** vault file or create a new one:

```bash
cd gitlab

# Option A: append to the existing vault (it will re-encrypt the whole file)
ansible-vault edit credentials.yml
# → add a line:  runner_registration_token: "glrt-xxxxxxxxxxxxxxxx"

# Option B: encrypt just the token string and paste the output into credentials.yml
ansible-vault encrypt_string 'glrt-xxxxxxxxxxxxxxxx' \
  --name 'runner_registration_token'
```

After editing, `credentials.yml` should contain (among other things):

```yaml
runner_registration_token: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...
```

---

## Step 5 — Configure Role Variables

The role ships with sensible defaults. Override only what you need. The cleanest approach is to pass variables in the playbook or via `group_vars`.

### Option A — Variables in the playbook (quick start)

`gitlab/pb_gitlab_runner.yml` is already wired up. Edit it to match your environment:

```yaml
# gitlab/pb_gitlab_runner.yml
- name: "Deploy GitLab Runner (Podman)"
  hosts: runner_hosts
  gather_facts: true
  become: true
  vars_files:
    - ./credentials.yml

  tasks:
    - name: "Include ro_gitlab_runner role"
      ansible.builtin.include_role:
        name: ro_gitlab_runner
      vars:
        gitlab_url: "https://gitlab.example.com"        # ← your GitLab URL
        gitlab_runner_registration_token: "{{ runner_registration_token }}"
        gitlab_runner_name: "{{ inventory_hostname }}-podman-runner"
        gitlab_runner_tags: "podman,linux,rhel"
        gitlab_runner_concurrent: 4
        gitlab_runner_executor: "shell"
```

### Option B — Group variables (recommended for multiple hosts)

```bash
mkdir -p gitlab/group_vars/runner_hosts
```

```yaml
# gitlab/group_vars/runner_hosts/runner.yml
gitlab_url: "https://gitlab.example.com"
gitlab_runner_registration_token: "{{ runner_registration_token }}"
gitlab_runner_name: "{{ inventory_hostname }}-podman"
gitlab_runner_tags: "podman,linux"
gitlab_runner_executor: "shell"
gitlab_runner_concurrent: 4
gitlab_runner_systemd_enabled: true
```

### Key variables at a glance

| Variable | What to set |
|---|---|
| `gitlab_url` | Full URL of your GitLab instance (e.g. `https://gitlab.mycompany.com`) |
| `gitlab_runner_registration_token` | From vault — the token obtained in Step 3 |
| `gitlab_runner_executor` | `shell` (simplest) or `docker` (for container-based jobs) |
| `gitlab_runner_concurrent` | How many jobs can run in parallel on this host |
| `gitlab_runner_tags` | Tags that `.gitlab-ci.yml` files will use to target this runner |

---

## Step 6 — Run the Playbook

```bash
cd gitlab

# Dry run first (check mode — no changes applied)
ansible-playbook pb_gitlab_runner.yml \
  -i inventory/hosts.yml \
  -l runner_hosts \
  --ask-vault-pass \
  --check \
  --diff

# Apply for real
ansible-playbook pb_gitlab_runner.yml \
  -i inventory/hosts.yml \
  -l runner_hosts \
  --ask-vault-pass
```

### Expected output

The run will proceed through these phases, each shown as a task group:

```
PLAY [Deploy GitLab Runner (Podman)] *****************************

TASK [ro_gitlab_runner : Assert: gitlab_url is defined] ✓
TASK [ro_gitlab_runner : Assert: registration token is defined] ✓
TASK [ro_gitlab_runner : Podman: Gather package facts] ✓
TASK [ro_gitlab_runner : Podman: Install packages (RHEL)] changed
TASK [ro_gitlab_runner : Podman: Enable and start podman.socket] changed
TASK [ro_gitlab_runner : Configure: Create GitLab Runner config directory] changed
TASK [ro_gitlab_runner : Configure: Create builds directory] changed
TASK [ro_gitlab_runner : Configure: Create cache directory] changed
TASK [ro_gitlab_runner : Configure: Render config.toml template] changed
TASK [ro_gitlab_runner : Container: Pull GitLab Runner image] changed
TASK [ro_gitlab_runner : Container: Create and start GitLab Runner container] changed
TASK [ro_gitlab_runner : Register: Register runner with GitLab] changed
TASK [ro_gitlab_runner : Systemd: Generate systemd unit file] changed
TASK [ro_gitlab_runner : Systemd: Enable and start the runner service] changed

PLAY RECAP *******************************************************
runner01 : ok=14 changed=9 unreachable=0 failed=0
```

> [!NOTE]
> On subsequent runs, most tasks will show `ok` (no change) — this is idempotency working as intended. Only tasks where state has genuinely drifted will show `changed`.

---

## Step 7 — Verify the Runner in GitLab

1. In GitLab, go to **Admin Area** → **CI/CD** → **Runners**.
2. Your new runner should appear with a **green dot** (online) and the name you configured (e.g. `runner01-podman-runner`).
3. Confirm the correct tags are listed.

You can also verify directly on the target VM:

```bash
# Check the container is running
podman ps --filter name=gitlab-runner

# Check the runner registered correctly
podman exec gitlab-runner gitlab-runner list

# Tail the runner logs
podman logs -f gitlab-runner

# Check systemd service
systemctl status container-gitlab-runner
```

---

## Step 8 — Run a Test CI/CD Job

Create a minimal `.gitlab-ci.yml` in any project that targets the new runner:

```yaml
# .gitlab-ci.yml
stages:
  - test

hello-runner:
  stage: test
  tags:
    - podman      # ← matches the tag on your runner
  script:
    - echo "Hello from the Podman GitLab Runner!"
    - uname -a
    - whoami
```

Commit and push. The job should be picked up within seconds and complete successfully.

---

## Understanding What the Role Does (Phase by Phase)

### Phase 1 — `assert.yml` — Pre-flight checks

Validates that required variables are set and have sensible values before any system change is made. The play fails immediately with a clear error message if anything is wrong.

### Phase 2 — `install_podman.yml` — Package installation

```
dnf install podman podman-plugins slirp4netns fuse-overlayfs   # RHEL
apt install podman uidmap slirp4netns fuse-overlayfs            # Debian/Ubuntu
zypper install podman                                           # SUSE
```

Then activates `podman.socket` via systemd so the Docker-compatible socket is available at `/run/podman/podman.sock`.

### Phase 3 — `configure.yml` — Directories and config

Creates:
- `/etc/gitlab-runner/` — config directory (bind-mounted into the container)
- `/var/lib/gitlab-runner/builds/` — build workspace
- `/var/lib/gitlab-runner/cache/` — runner cache

Renders `config.toml` from the Jinja2 template **only on first run** (if the file doesn't exist yet). After registration, GitLab Runner manages this file itself.

### Phase 4 — `container.yml` — Image and container lifecycle

```
podman pull docker.io/gitlab/gitlab-runner:latest
```

Creates the container with these bind mounts:

| Host path | Container path | Purpose |
|---|---|---|
| `/etc/gitlab-runner` | `/etc/gitlab-runner` | Config and certs |
| `/var/lib/gitlab-runner/builds` | `/builds` | CI job workspaces |
| `/var/lib/gitlab-runner/cache` | `/cache` | Runner cache |
| `/run/podman/podman.sock` | `/run/podman/podman.sock` | Container engine access |

If the image is updated on a subsequent run, the container is **automatically recreated** with the new image.

### Phase 5 — `register.yml` — Idempotent registration

Reads the existing `config.toml` and extracts any `token =` value. If one is found, registration is **skipped** — preventing duplicate runners from being created in GitLab on re-runs.

If no token exists, runs:

```bash
podman exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.example.com" \
  --registration-token "***" \
  --executor "shell" \
  ...
```

The registration token is passed with `no_log: true` so it never appears in Ansible output.

### Phase 6 — `systemd.yml` — Boot persistence

Generates a systemd unit file via:

```bash
podman generate systemd --name gitlab-runner --restart-policy always --new
```

Installs it to `/etc/systemd/system/` and enables it so the runner container starts automatically after a reboot.

---

## Customisation Examples

### Use the `docker` executor with Podman socket

Run jobs inside isolated containers (like Docker-in-Docker, but with Podman):

```yaml
gitlab_runner_executor: "docker"
gitlab_runner_default_image: "alpine:3.19"
gitlab_runner_enable_podman_socket: true
gitlab_runner_container_env:
  - "DOCKER_HOST=unix:///run/podman/podman.sock"
```

Then in `.gitlab-ci.yml`:

```yaml
build:
  image: python:3.12
  tags: [podman]
  script:
    - pip install -r requirements.txt
    - python -m pytest
```

### Pin to a specific runner version

```yaml
gitlab_runner_image: "docker.io/gitlab/gitlab-runner:v17.3.0"
```

### Project-locked runner

```yaml
gitlab_runner_locked: true
gitlab_runner_run_untagged: false
gitlab_runner_tags: "my-project,deploy"
```

### High-throughput build farm

```yaml
gitlab_runner_concurrent: 16
gitlab_runner_check_interval: 1
gitlab_runner_builds_dir: "/fast-nvme/builds"
gitlab_runner_cache_dir: "/fast-nvme/cache"
```

### Privileged mode (for container builds)

```yaml
gitlab_runner_privileged: true   # ⚠️ Only when absolutely required
```

> [!CAUTION]
> Privileged mode grants the job container nearly full root access to the host kernel. Only enable this if your pipelines build container images and you accept the security trade-off.

---

## Day-2 Operations

### Re-running the playbook (idempotent)

The role is safe to re-run at any time. On subsequent executions:

- Packages already installed → `ok` (no change)
- Config directory already present → `ok`
- `config.toml` already exists → skipped (not overwritten)
- Container already running with correct image → `ok`
- Runner already registered → `ok` (token found in config.toml)
- Systemd service already enabled → `ok`

### Updating the runner image

Change `gitlab_runner_image` to a newer tag and re-run:

```bash
ansible-playbook pb_gitlab_runner.yml \
  -i inventory/hosts.yml \
  -l runner_hosts \
  --ask-vault-pass \
  -e "gitlab_runner_image=docker.io/gitlab/gitlab-runner:v17.5.0"
```

The role detects the image digest changed, removes the old container, and starts a new one with the updated image. The runner re-registers automatically (token preserved in `config.toml`).

### Unregistering and removing the runner

To cleanly remove a runner:

```bash
# On the target VM
podman exec gitlab-runner gitlab-runner unregister --all-runners
systemctl disable --now container-gitlab-runner
podman rm -f gitlab-runner
podman rmi docker.io/gitlab/gitlab-runner:latest
rm -rf /etc/gitlab-runner /var/lib/gitlab-runner
```

In GitLab, the runner will show as offline and can be deleted from **Admin > CI/CD > Runners**.

### Viewing runner logs

```bash
# Live logs
podman logs -f gitlab-runner

# Last 100 lines
podman logs --tail 100 gitlab-runner

# Via journald (if systemd unit is active)
journalctl -u container-gitlab-runner -f
```

### Checking runner health

```bash
podman exec gitlab-runner gitlab-runner verify
```

---

## Troubleshooting

### Runner appears offline in GitLab

1. Check the container is running: `podman ps --filter name=gitlab-runner`
2. Check logs for connection errors: `podman logs gitlab-runner`
3. Verify network connectivity from the VM to GitLab: `curl -v https://gitlab.example.com/-/readiness`
4. Check the URL in `config.toml`: `cat /etc/gitlab-runner/config.toml`

### "Error: runner already registered" on re-run

This should not happen with this role (the registration task is idempotent). If it does:

```bash
cat /etc/gitlab-runner/config.toml | grep token
```

If a token is present but the runner shows as offline in GitLab, the runner may have been deleted from the GitLab side. Unregister locally and re-run the playbook:

```bash
podman exec gitlab-runner gitlab-runner unregister --all-runners
# Delete config.toml so the role re-renders and re-registers
rm /etc/gitlab-runner/config.toml
ansible-playbook pb_gitlab_runner.yml -i inventory/hosts.yml -l runner_hosts --ask-vault-pass
```

### "Permission denied" accessing Podman socket

Check the socket exists and has correct permissions:

```bash
ls -la /run/podman/podman.sock
systemctl status podman.socket
```

On SELinux-enforcing systems (RHEL), the `:Z` volume label in the role ensures proper labelling. If issues persist:

```bash
ausearch -m avc -ts recent | grep podman
```

### Jobs stuck in "pending" state

1. Confirm the runner is online in GitLab UI.
2. Confirm the job's `tags:` in `.gitlab-ci.yml` match the runner's tags exactly.
3. Check `gitlab_runner_run_untagged` — if set to `false`, untagged jobs will not be picked up.
4. Check `gitlab_runner_concurrent` — if all slots are busy, jobs queue.

### `podman: command not found` after role run

This can happen if `gather_facts` is `false` and `ansible_os_family` is undefined. Ensure `gather_facts: true` in your playbook (the default) or set `ansible_os_family` explicitly.
