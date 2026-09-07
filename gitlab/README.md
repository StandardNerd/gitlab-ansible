# Gitlab

Ansible Playbook to provision and decommission Gitlab Server

## Quickstart

Install Gitlab Server:

```bash
ansible-playbook pb_gitlab_present.yml -i inventory/hosts.yml --extra-vars "ip_address_v4=192.168.1.135"
```
