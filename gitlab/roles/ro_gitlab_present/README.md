# ro_gitlab_present

Ansible role for installing and configuring GitLab CE/EE on RHEL 9 and Ubuntu Noble 24.04.

## Supported OS
- RHEL 9
- Ubuntu 24.04 (Noble)

## Variables

| Variable | Default | Description |
|---|---|---|
| `gls_edition` | `ce` | ce or ee |
| `gls_version` | `latest` | GitLab version to install |
| `gls_ssl_enabled` | `true` | Enable SSL |
| `gls_ssl_cert_path` | `/etc/gitlab/ssl/{{ gls_domain }}.crt` | Path to SSL certificate |
| `gls_ssl_key_path` | `/etc/gitlab/ssl/{{ gls_domain }}.key` | Path to SSL key |
| `gls_ssl_self_signed` | `true` | Generate self-signed certificate |
| `gls_domain` | (Required) | GitLab domain |
| `gls_external_url` | `http://{{ gls_domain }}` | GitLab external URL |
| `gls_admin_password` | `gls_initial_adm_pwd` | Initial admin password |

## SSL Configuration
By default, this role uses self-signed certificates. If you want to use your own certificates, set `gls_ssl_self_signed: false` and ensure that the certificate and key are deployed to the paths specified by `gls_ssl_cert_path` and `gls_ssl_key_path` before running this role.

## Example Playbook

```yaml
- hosts: all
  roles:
    - role: ro_gitlab_present
      vars:
        gls_domain: gitlab.example.com
        gls_external_url: "https://gitlab.example.com"
        gls_admin_password: "super_secret_password"
```

## Structure
- `tasks/main.yml` - Main entrypoint
- `tasks/assert.yml` - Variable validation
- `tasks/prepare_redhat.yml` - RedHat environment preparation
- `tasks/prepare_debian.yml` - Debian environment preparation
- `tasks/install_redhat.yml` - RedHat package installation
- `tasks/install_debian.yml` - Debian package installation
- `tasks/ssl.yml` - SSL setup
- `tasks/configure.yml` - GitLab reconfigure
- `tasks/gitlab_ruby_configuration.yml` - Post-install script configuration
- `tasks/cleanup.yml` - Cleanup temporary scripts
