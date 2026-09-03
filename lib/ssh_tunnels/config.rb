# frozen_string_literal: true

module SshTunnels
  # Loads and validates a YAML configuration file and builds Tunnel objects
  # from it. Invalid configuration raises ConfigError rather than exiting so
  # that a live reload can report the problem and carry on unchanged.
  class Config
    REQUIRED_TUNNEL_KEYS = %w[host remote_port].freeze

    attr_reader :path

    def self.load(path)
      raise ConfigError, "Unable to locate configuration file: #{path}" unless File.exist?(path)

      new(path, YAML.safe_load_file(path))
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML: #{e.problem} (line #{e.line}, column #{e.column})"
    end

    def initialize(path, data)
      @path = path
      @data = data
      validate
    end

    def mtime
      File.mtime(@path)
    rescue Errno::ENOENT
      nil
    end

    def tunnels(user, passphrase)
      tunnel_configs.map do |name, tunnel_config|
        settings = { 'local_ip' => default_local_ip }.merge(tunnel_config)
        Tunnel.new(name, user, settings, gateway_for(tunnel_config), passphrase)
      end
    end

    private

    def validate
      validate_structure
      errors = tunnel_configs.flat_map { |name, tunnel_config| tunnel_errors(name, tunnel_config) }
      raise ConfigError, errors.join("\n") unless errors.empty?
    end

    def validate_structure
      raise ConfigError, 'Configuration file must contain a YAML map.' unless @data.is_a?(Hash)
      raise ConfigError, 'Configuration file must provide `tunnels` section.' unless @data.key?('tunnels')
      raise ConfigError, '`tunnels` section must be a map.' unless tunnel_configs.is_a?(Hash)
      raise ConfigError, '`gateways` section must be a map.' unless gateways.is_a?(Hash)
    end

    def tunnel_errors(name, tunnel_config)
      return ["Tunnel `#{name}` must be a map."] unless tunnel_config.is_a?(Hash)

      missing = REQUIRED_TUNNEL_KEYS.reject { |key| tunnel_config.key?(key) }
      missing.map { |key| "Tunnel `#{name}` must provide `#{key}`." } + gateway_errors(name, tunnel_config)
    end

    def gateway_errors(name, tunnel_config)
      if tunnel_config.key?('gateway')
        gateway = tunnel_config.fetch('gateway')
        return [] if gateways.key?(gateway)

        ["Tunnel `#{name}` references unknown gateway `#{gateway}`."]
      elsif default_gateway.nil?
        ["Tunnel `#{name}` must provide `gateway` key or define a top-level `default_gateway` configuration."]
      else
        []
      end
    end

    def gateway_for(tunnel_config)
      return default_gateway unless tunnel_config.key?('gateway')

      gateways.fetch(tunnel_config.fetch('gateway'))
    end

    def tunnel_configs
      @data.fetch('tunnels')
    end

    def gateways
      @data.fetch('gateways', {})
    end

    def default_gateway
      @data.fetch('default_gateway', nil)
    end

    def default_local_ip
      @data.fetch('default_local_ip', nil)
    end
  end
end
