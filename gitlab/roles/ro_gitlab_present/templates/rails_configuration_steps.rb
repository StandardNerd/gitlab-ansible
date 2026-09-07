puts "Create admin token"
token = User.find_by_id(1).personal_access_tokens.create(name: "admin_token", scopes: ["api"], expires_at: Time.now + 11.months)
token.set_token("admin_token")
token.save!
puts "Admin token created: #{token.token}"

puts "Update admin user"
admin_user = User.find_by_id(1)
admin_user.username = "{{ gls_admin_username }}"
admin_user.password = "{{ gls_admin_password }}"
admin_user.password_confirmation = "{{ gls_admin_password }}"
admin_user.save!

puts "Update Appearance"
appearance = Appearance.first_or_create
appearance.logo = File.open("{{ gitlab_rb_scripts_tempdir.path }}/KAPO-Logo.SVG")
appearance.header_logo = File.open("{{ gitlab_rb_scripts_tempdir.path }}/KAPO-Logo.SVG")
appearance.save!


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
safe_create_user('joonki', 'joon-ki.choi@swisscom.com', 'Joon-Ki Choi', 'SecurePassword123!', admin: true)