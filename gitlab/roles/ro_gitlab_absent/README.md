# Role: `ro_gitlab_absent`

Completely removes a GitLab CE/EE installation from RHEL 9 or Ubuntu Noble (24.04) hosts.

## What it does

| Phase | Task file | Description |
|---|---|---|
| 1 | `stop.yml` | Runs `gitlab-ctl stop`, disables the `gitlab-runsvdir` service, runs `gitlab-ctl kill` |
| 2 | `uninstall_redhat.yml` | Removes the package via `dnf` and deletes the YUM repo file |
| 2 | `uninstall_debian.yml` | Purges the package via `apt`, removes the APT sources list and GPG key |
| 3 | `firewall.yml` | Closes HTTP/HTTPS ports in `firewalld` (RHEL) or `ufw` (Ubuntu) |
| 4 | `cleanup.yml` | Removes data directories, SSL certs, system users/groups, leftover systemd units |

## Supported OS

| OS | Package manager | Firewall |
|---|---|---|
| RHEL 9 / Rocky / AlmaLinux 9 | `dnf` | `firewalld` |
| Ubuntu Noble 24.04 / Debian 12 | `apt` | `ufw` |

## Variables

| Variable | Default | Description |
|---|---|---|
| `gla_package_name` | `gitlab-ce` | Package to remove (`gitlab-ce` or `gitlab-ee`) |
| `gla_remove_data` | `true` | Remove `/etc/gitlab`, `/var/opt/gitlab`, `/var/log/gitlab`, `/opt/gitlab` |
| `gla_remove_repository` | `true` | Remove the GitLab yum/apt repository |
| `gla_remove_users` | `false` | Remove GitLab system users (`git`, `gitlab-www`, etc.) |
| `gla_remove_firewall_rules` | `true` | Close HTTP/HTTPS firewall ports |
| `gla_remove_ssl` | `true` | Remove SSL certificates from `/etc/gitlab/ssl` |
| `gla_firewall_enabled` | `true` | Set to `false` to skip all firewall tasks |

## Usage

```bash
# Remove GitLab from a server
ansible-playbook pb_gitlab_absent.yml \
  -i inventory/hosts.yml \
  -l gitlab-server \
  --ask-vault-pass

# Remove GitLab but keep the data directories
ansible-playbook pb_gitlab_absent.yml \
  -i inventory/hosts.yml \
  -l gitlab-server \
  -e "gla_remove_data=false" \
  --ask-vault-pass

# Also remove GitLab system users
ansible-playbook pb_gitlab_absent.yml \
  -i inventory/hosts.yml \
  -l gitlab-server \
  -e "gla_remove_users=true" \
  --ask-vault-pass
```

## Idempotency

The role is fully idempotent. If GitLab is not installed, it detects this and skips all removal tasks. Running the role a second time produces no changes.

## License

MIT-0
