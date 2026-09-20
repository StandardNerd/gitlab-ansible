# Role: `ro_gitlab_runner_absent`

Decommissions and cleanly removes a **GitLab Runner** deployed via a **Podman container** on RHEL 9 or Ubuntu Noble (24.04) hosts.

## What it does

| Phase | Task file | Description |
|---|---|---|
| 0 | `assert.yml` | Validates required role parameters |
| 1 | `unregister.yml` | Unregisters all runners from the GitLab instance via `gitlab-runner unregister --all-runners` (using active container or ephemeral fallback) |
| 2 | `systemd.yml` | Stops and disables `container-gitlab-runner.service`, removes unit file, clears `.ctr-id`, reloads daemon, and resets failed states |
| 3 | `container.yml` | Stops and removes the runner Podman container and optionally deletes the OCI image |
| 4 | `cleanup.yml` | Removes host directories (`/etc/gitlab-runner`, `/var/lib/gitlab-runner`) |
| 5 | `uninstall_podman.yml` | (Optional) Stops `podman.socket` and uninstalls Podman packages & config |

## Variables

| Variable | Default | Description |
|---|---|---|
| `gitlab_url` | `https://192.168.1.129` | URL of the GitLab instance |
| `glra_container_name` | `gitlab-runner` | Podman container name |
| `glra_runner_image` | `docker.io/gitlab/gitlab-runner:latest` | OCI image for the runner |
| `glra_config_dir` | `/etc/gitlab-runner` | Host directory containing `config.toml` |
| `glra_builds_dir` | `/var/lib/gitlab-runner/builds` | Host directory for builds |
| `glra_cache_dir` | `/var/lib/gitlab-runner/cache` | Host directory for runner cache |
| `glra_systemd_service` | `container-{{ glra_container_name }}` | Systemd unit name |
| `glra_unregister` | `true` | Unregister runner from GitLab before removal |
| `glra_remove_data` | `true` | Remove configuration, builds, and cache directories |
| `glra_remove_image` | `true` | Remove the GitLab Runner OCI image |
| `glra_remove_podman` | `false` | Remove Podman packages (set to `true` if no other workloads use Podman) |
| `glra_remove_podman_socket` | `false` | Disable and stop `podman.socket` |

## Usage

```bash
# Decommission GitLab Runner
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml

# Decommission and also remove Podman packages
ansible-playbook pb_gitlab_runner_absent.yml -i inventory/hosts.yml -e "glra_remove_podman=true"
```

## Idempotency

The role is fully idempotent. If the container, service, image, or directories do not exist, all tasks are safely handled without failing.

## License

MIT-0
