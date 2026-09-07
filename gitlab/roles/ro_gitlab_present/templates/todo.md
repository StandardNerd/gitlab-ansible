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

```bash
sudo gitlab-ctl reconfigure
sudo gitlab-rake gitlab:ldap:check
```


# create initial admin user
def safe_create_user(username, email, name, password, admin: false)
  user = User.new(
    username: username,
    email: email,
    name: name,
    password: password,
    password_confirmation: password,
    admin: admin
  )
  
  user.skip_confirmation!
  
  # Try to get default organization
  begin
    org = Organizations::Organization.default_organization
    
    if org.nil?
      # Create default organization if it doesn't exist
      org = Organizations::Organization.create!(
        name: 'Default',
        path: 'default'
      )
    end
    
    # Create namespace with organization
    namespace = Namespaces::UserNamespace.new(
      name: user.name,
      path: user.username,
      owner: user,
      organization: org
    )
    
    user.namespace = namespace
    
  rescue NameError
    # Older GitLab version without organizations
    user.build_namespace
  end
  
  user.save!
  puts "User created: #{username}"
  user
end

# Usage:
safe_create_user('joonki', 'joon-ki.choi@swisscom.com', 'Joon-Ki Choi', 'BernBresenham!', admin: true)