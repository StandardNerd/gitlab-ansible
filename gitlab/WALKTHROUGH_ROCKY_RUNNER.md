# GitLab Runner Deployment Walkthrough (Rocky Linux 10 & Podman)

This walkthrough documents the end-to-end deployment and registration of a GitLab CI/CD Runner on **Rocky Linux 10** using Podman, orchestrated via Ansible to communicate with the GitLab CE instance on **`192.168.64.6`**.

---

## 1. Architecture & Network Topology

The infrastructure runs on local UTM virtual machines connected via macOS shared bridge networking (`192.168.64.0/24`):

```mermaid
flowchart TD
    subgraph ControlHost["Ansible Control Node (Mac)"]
        AC["Ansible Core 2.20"]
        VP["/etc/ansible/vaultpass.txt"]
        CR["credentials.yml"]
        INV["inventory/hosts.yml"]
        PB["pb_gitlab_runner.yml"]
    end

    subgraph ServerVM["GitLab Server (192.168.64.6)"]
        NGX["Nginx (HTTPS :443)"]
        CERT["TLS Certificate (SAN: 192.168.64.6)"]
        RAILS["GitLab Rails / Puma"]
        TOKEN["Registration Token: J2_8z-xz_oh19Pv-RvKN"]
    end

    subgraph RunnerVM["GitLab Runner Node (192.168.64.8)"]
        SYS["Systemd: container-gitlab-runner.service"]
        PODMAN["Podman 5.8.2 Engine"]
        CTR["Container: gitlab-runner:latest"]
        CFG["/etc/gitlab-runner/config.toml"]
        CACERT["/etc/gitlab-runner/certs/192.168.64.6.crt"]
        BUILDS["/var/lib/gitlab-runner/builds"]
        CACHE["/var/lib/gitlab-runner/cache"]
    end

    ControlHost -->|SSH port 22 (jono / sudo)| ServerVM
    ControlHost -->|SSH port 22 (jono / sudo)| RunnerVM
    CTR -->|HTTPS :443 (TLS verified via SAN cert)| NGX
    SYS -->|Manages lifecycle| CTR
```

### Node Specifications

| Component | Node / IP | OS / Distribution | Role & Key Services |
| :--- | :--- | :--- | :--- |
| **Control Host** | Local Mac (`192.168.64.1`) | macOS (Darwin ARM64) | Ansible Core 2.20, `ansible.posix`, `containers.podman` |
| **GitLab Server** | `192.168.64.6` | Rocky Linux 10.2 (el10) | GitLab CE Omnibus 17.x, Nginx, Puma, Gitaly, PostgreSQL |
| **GitLab Runner** | `192.168.64.8` | Rocky Linux 10.2 (el10) | Podman 5.8.2, `container-gitlab-runner.service`, `gitlab-runner:latest` |

---

## 2. Pre-requisites & Root-Cause Resolutions

During the initial deployment, several environmental and distribution-specific blockers were identified and resolved:

### 1. UTM Cloned MAC Address Conflict
- **Symptom**: Runner VM started up with MAC address `E6:61:56:73:68:05`, exactly identical to the GitLab Server VM. This caused severe ARP and Ethernet switching flapping on `bridge100`, making both VMs intermittently unreachable.
- **Resolution**:
  - Configured NetworkManager on the runner to use cloned MAC `E6:61:56:73:68:07`:
    ```bash
    nmcli conn mod enp0s1 802-3-ethernet.cloned-mac-address e6:61:56:73:68:07
    nmcli conn up enp0s1
    ```
  - Runner was assigned a clean, persistent DHCP lease at **`192.168.64.8`**.

### 2. User Authentication & Sudo Provisioning
- **Symptom**: `credentials.yml` required user `jono` with password `dexter33143`, but the fresh Rocky 10 VM only had `root`.
- **Resolution**: Created user `jono`, added to `wheel` group, configured password `dexter33143`, and enabled passwordless sudo in `/etc/sudoers.d/jono`.

### 3. RedHat/Rocky Linux 10 Package Compatibility
- **Symptom**: The default RedHat package list in the role contained `podman-plugins`, which does not exist in Enterprise Linux 10 (functionality was absorbed into Podman 5 and Netavark). Additionally, `openssl` was missing on the minimal OS installation.
- **Resolution**: Updated `roles/ro_gitlab_runner/vars/RedHat.yml`:
  ```yaml
  _podman_pkgs:
    - podman
    - slirp4netns
    - fuse-overlayfs
    - container-selinux
    - openssl
  ```

### 4. SELinux Boolean for cgroups v2
- **Symptom**: The task `Enable container_manage_cgroup SELinux boolean` failed because `container_manage_cgroup` is obsolete and removed in EL 9 and EL 10 where cgroups v2 is default.
- **Resolution**: Updated `roles/ro_gitlab_runner/tasks/install_podman_redhat.yml` with a conditional guard:
  ```yaml
  - name: "Configure: Enable container_manage_cgroup SELinux boolean"
    ansible.posix.seboolean:
      name: container_manage_cgroup
      state: true
      persistent: true
    when:
      - gitlab_runner_configure_selinux | bool
      - ansible_distribution_major_version | int < 9
  ```

### 5. Live Registration Token Extraction
- **Resolution**: Queried the live registration token from the GitLab Rails console on `192.168.64.6`:
  ```bash
  gitlab-rails runner -e production \
    'puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token'
  # Output: J2_8z-xz_oh19Pv-RvKN
  ```

### 6. Runner Request Bottleneck & Endpoints Configuration
- **Symptom**: GitLab Runner logged:
  - `Issues found: Request bottleneck: 1 runners have request_concurrency=1, causing job delays during long polling`
  - `listen_address not defined, metrics & debug endpoints disabled`
  - `[session_server].listen_address not defined, session endpoints disabled`
- **Resolution**:
  - Configured `request_concurrency = 4` inside `[[runners]]` to match concurrency and prevent long-polling serialization bottlenecks.
  - Configured `listen_address = "0.0.0.0:9252"` for Prometheus metrics and debug pprof endpoints.
  - Configured `listen_address = "0.0.0.0:8093"` with `advertise_address = "192.168.64.8:8093"` in `[session_server]` for interactive web terminals.
  - Added role defaults and convergence tasks in `ro_gitlab_runner` so these settings persist across redeployments.

---

## 3. Configuration & Inventory Files

### Inventory File: `inventory/hosts.yml`

```yaml
all:
  hosts:
    gitlab-server:
      ansible_host: 192.168.64.6
      ansible_user: jono
      ansible_password: "{{ ansible_user_password }}"
    gitlab-runner:
      ansible_host: 192.168.64.8
      ansible_user: jono
      ansible_password: "{{ ansible_user_password }}"
```

### Playbook: `pb_gitlab_runner.yml`

```yaml
---
- name: "Deploy GitLab Runner (Podman)"
  hosts: gitlab-runner
  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
  gather_facts: true
  become: true
  vars_files:
    - ./credentials.yml

  tasks:
    - name: "Include ro_gitlab_runner role"
      ansible.builtin.include_role:
        name: ro_gitlab_runner
      vars:
        gitlab_runner_registration_token: "{{ runner_registration_token | default('4gcyYJNxXUxMZKji5WpA') }}"
        gitlab_runner_name: "{{ inventory_hostname }}-podman-runner"
        gitlab_runner_tags: "podman,linux"
        gitlab_runner_concurrent: 4
        gitlab_runner_executor: "shell"
```

---

## 4. Execution Commands

### Step 1: Pre-flight Ping Check

Verify Ansible connectivity and SSH authentication across both nodes:

```bash
ansible all -i inventory/hosts.yml -e @credentials.yml -m ping
```

Expected output:
```text
gitlab-runner | SUCCESS => {"ping": "pong"}
gitlab-server | SUCCESS => {"ping": "pong"}
```

### Step 2: Run the Playbook

Execute the deployment playbook with the server URL and registration token:

```bash
ansible-playbook pb_gitlab_runner.yml \
  -i inventory/hosts.yml \
  -e "gitlab_url=https://192.168.64.6" \
  -e "runner_registration_token=J2_8z-xz_oh19Pv-RvKN"
```

#### What Happens During Execution:
1. **OS Fact Gathering & Assertions**: Validates `gitlab_url`, `gitlab_runner_registration_token`, `concurrent`, and `executor`.
2. **Package Installation**: Installs `podman`, `slirp4netns`, `fuse-overlayfs`, `container-selinux`, `openssl`, and `policycoreutils-python-utils` via DNF.
3. **Socket Setup**: Starts and enables `podman.socket`.
4. **Directory Preparation**: Creates `/etc/gitlab-runner`, `/etc/gitlab-runner/certs`, `/var/lib/gitlab-runner/builds`, and `/var/lib/gitlab-runner/cache`.
5. **TLS Certificate Fetch**: Downloads the GitLab server self-signed public certificate via `openssl s_client` and saves it to `/etc/gitlab-runner/certs/192.168.64.6.crt`.
6. **Container Startup**: Pulls `docker.io/gitlab/gitlab-runner:latest` and launches the Podman container with SELinux `:Z` bind-mount volumes.
7. **Runner Registration**: Executes `gitlab-runner register` non-interactively with `--tls-ca-file`, registering the runner to `https://192.168.64.6`.
8. **Systemd Persistence**: Generates and enables `container-gitlab-runner.service` using `podman generate systemd`.

---

## 5. Verification & Health Checks

### Check Systemd Service on the Runner Node (`192.168.64.8`):

```bash
ansible gitlab-runner -i inventory/hosts.yml -e @credentials.yml -b -m command \
  -a "systemctl status container-gitlab-runner --no-pager"
```

Expected output confirms `active (running)`:
```text
● container-gitlab-runner.service - Podman container-gitlab-runner.service
     Loaded: loaded (/etc/systemd/system/container-gitlab-runner.service; enabled; preset: disabled)
     Active: active (running)
```

### Verify Runner Health Inside Container:

```bash
ansible gitlab-runner -i inventory/hosts.yml -e @credentials.yml -b -m command \
  -a "podman exec gitlab-runner gitlab-runner verify"
```

Output:
```text
Runtime platform                                    arch=arm64 os=linux pid=14 revision=33227fd4 version=19.5.3
Running in system-mode.
Verifying runner... is alive                        correlation_id=01M7APC952GFK21QGT6RC5TSGE runner=gszHFax7n runner_name=gitlab-runner-podman-runner
```

### Verify Runner in GitLab Server Console (`192.168.64.6`):

```bash
ansible gitlab-server -i inventory/hosts.yml -e @credentials.yml -b -m command \
  -a "gitlab-rails runner -e production 'Ci::Runner.all.each { |r| puts \"ID: #{r.id}, Description: #{r.description}, Status: #{r.status}, Active: #{r.active}\" }'"
```

Output:
```text
ID: 1, Description: gitlab-runner-podman-runner, Status: online, Active: true
```

### Administrator Web & API Login Credentials

- **Web URL**: `https://192.168.64.6/users/sign_in` *(Bypass browser self-signed TLS warning via "Advanced > Proceed")*
- **Primary Username**: `gls_admin`
- **Fallback Username**: `root`
- **Password**: `gls_initial_adm_pwd`
- **API Private Token**: `admin_token` (bound to `gls_admin`)

---

## 6. Day-2 Operations

### View Runner Container Logs:
```bash
ansible gitlab-runner -i inventory/hosts.yml -e @credentials.yml -b -m command \
  -a "podman logs --tail 50 gitlab-runner"
```

### Restart Runner Service:
```bash
ansible gitlab-runner -i inventory/hosts.yml -e @credentials.yml -b -m systemd \
  -a "name=container-gitlab-runner state=restarted"
```

### Decommission Runner:
To completely unregister and remove the container, service, and cache directories:
```bash
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml
```
