CONFIG = YAML.load_file( "#{RAILS_ROOT}/config/config.yml" )[RAILS_ENV]

# give precedence to settings coming from env
CONFIG['rally_username'] = ENV['RALLY_USERNAME'] if ENV['RALLY_USERNAME']
CONFIG['rally_password'] = ENV['RALLY_PASSWORD'] if ENV['RALLY_PASSWORD']
