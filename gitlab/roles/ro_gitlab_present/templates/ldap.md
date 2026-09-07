# LDAP Configuration

bare minimum configuration:

```ruby
gitlab_rails['ldap_enabled'] = true
gitlab_rails['ldap_servers'] = YAML.load <<-'EOS'
  main:
    label: 'Active Directory'
    host: 'ad.company.com'
    port: 389
    uid: 'sAMAccountName'
    bind_dn: 'CN=GitLab Service,CN=Users,DC=company,DC=com'
    password: 'service_account_password'
    encryption: 'plain'
    base: 'DC=company,DC=com'
EOS
```

Enable Configuration and test LDAP connection:

```bash
sudo gitlab-ctl reconfigure
sudo gitlab-rake gitlab:ldap:check
```


Multiple LDAP Servers Configuration (not a failover between LDAP Servers - used as a separate login option to different LDAP directories)

```ruby
gitlab_rails['ldap_enabled'] = true
gitlab_rails['ldap_servers'] = YAML.load <<-'EOS'
  main:
    label: 'Primary LDAP'
    host: 'ldap1.example.com'
    port: 389
    uid: 'uid'
    bind_dn: 'cn=gitlab-primary,ou=services,dc=example,dc=com'
    password: 'password1'
    encryption: 'start_tls'
    base: 'dc=example,dc=com'
  
  secondary:
    label: 'Secondary LDAP'
    host: 'ldap2.example.com'
    port: 389
    uid: 'uid'
    bind_dn: 'cn=gitlab-secondary,ou=services,dc=company,dc=com'
    password: 'password2'
    encryption: 'start_tls'
    base: 'dc=company,dc=com'
EOS
```


sudo gitlab-ctl reconfigure
# Test all configured LDAP servers
sudo gitlab-rake gitlab:ldap:check
# Test a specific LDAP server
sudo gitlab-rake gitlab:ldap:check LDAP_SERVER_ID='Secondary LDAP'
