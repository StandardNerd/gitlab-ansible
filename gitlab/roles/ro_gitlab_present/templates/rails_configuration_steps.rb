puts "Configure Admin User and Token"
admin_user = User.find_by_username("{{ gls_admin_username }}") || User.find_by_username("root") || User.find_by_id(1) || User.admins.first

if admin_user
  puts "Updating admin user: #{admin_user.username} -> {{ gls_admin_username }}"
  admin_user.username = "{{ gls_admin_username }}"
  admin_user.password = "{{ gls_admin_password }}"
  admin_user.password_confirmation = "{{ gls_admin_password }}"
  admin_user.save!

  token_name = "{{ gls_admin_token_name | default('admin_token') }}"
  target_token = "{{ gls_admin_api_token | default('admin_token') }}"
  existing_token = admin_user.personal_access_tokens.find_by(name: token_name)

  if existing_token
    puts "Admin token already exists: #{existing_token.name}"
    existing_token.set_token(target_token)
    existing_token.revoked = false
    existing_token.expires_at = Time.now + 11.months if existing_token.expired?
    existing_token.save!
    puts "Admin token updated: #{token_name}"
  else
    token = admin_user.personal_access_tokens.create!(
      name: token_name,
      scopes: ["api"],
      expires_at: Time.now + 11.months
    )
    token.set_token('retrieve_runner_token')
    token.save!
    puts "Admin token created: #{token.token}"
  end
  puts "ADMIN_API_TOKEN: #{target_token}"
else
  puts "Warning: Admin user not found to configure token"
end

puts "Update Appearance"
appearance = Appearance.first_or_create
logo_file = "{{ gitlab_rb_scripts_tempdir.path }}/KAPO-Logo.SVG"
if File.exist?(logo_file)
  appearance.logo = File.open(logo_file)
  appearance.header_logo = File.open(logo_file)
  appearance.save!
  puts "Appearance logo updated"
end

# Retrieve instance runner registration token
begin
  runner_reg_token = Gitlab::CurrentSettings.current_application_settings.runners_registration_token
  puts "RUNNER_REGISTRATION_TOKEN: #{runner_reg_token}"
rescue => e
  puts "Could not retrieve runner registration token: #{e.message}"
end
