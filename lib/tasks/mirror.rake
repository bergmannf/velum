require "yaml"

MIRROR_CONFIGURATION_FILE = "/etc/docker/mirrors.yaml".freeze

# Insert Registry and RegistryMirror objects based on a configuration file.
# The config file format is expected to be:
#
# <registry_name>:
#   url: https://registry.suse.com
#   mirrors:
#     <mirror_name>:
#       url: https://airgapped.suse.com
#     <mirror_name_2>:
#       url: https://airgapped2.suse.com
def insert_from_config(config_file)
  configuration = YAML.load_file(config_file)
  configuration.each_key do |registry_name|
    registry_configuration = configuration[registry_name]
    registry_url = registry_configuration["url"]
    registry = Registry.create(name: registry_name,
                               url:  registry_url)
    registry_configuration["mirrors"].each_key do |mirror_name|
      mirror_config = registry_configuration["mirrors"][mirror_name]
      mirror_url = mirror_config["url"]
      RegistryMirror.create(name:     mirror_name,
                            url:      mirror_url,
                            registry: registry)
    end
  end
rescue ActiveRecord::RecordInvalid
  puts "RegistryMirrors could not be read from #{config_file}"
end

namespace :mirror do
  desc "Import configured mirrors from yaml configuration"
  task :import, [:config] => :environment do |_, args|
    config_file = args[:config] || MIRROR_CONFIGURATION_FILE
    unless File.exist?(config_file)
      puts "Mirror configuration file does not exist: #{config_file}"
      exit(1)
    end
    insert_from_config(config_file)
  end
end
