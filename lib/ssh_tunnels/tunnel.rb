# frozen_string_literal: true

module SshTunnels
  # SSH Tunnel
  class Tunnel
    attr_reader :name, :error

    def initialize(name, user, config, gateway, passphrase)
      @name = name
      @user = user
      @config = config
      @passphrase = passphrase
      @config = config
      @gateway = gateway
      @connection = nil
    end

    def to_s
      base = "#{local_port}:#{remote_host}:#{remote_port}"
      return base unless @error

      "#{base} (#{@error})"
    end

    def toggle
      active? ? shutdown : open
    end

    def open
      @connection = Net::SSH::Gateway.new(@gateway.fetch('host'), @gateway.fetch('user', @user), options)
      @connection.open(remote_host, remote_port, local_port)
    rescue StandardError => e
      shutdown
      raise
    end

    def active?
      return false if @connection.nil?

      @connection.active?
    end

    def shutdown
      @connection&.shutdown!
    end

    private

    def remote_host
      @config.fetch('host')
    end

    def remote_port
      @config.fetch('remote_port')
    end

    def local_port
      @config.fetch('local_port', remote_port)
    end

    def options
      {
        keepalive: true,
        keepalive_interval: 5,
        port: @gateway.fetch('port', 22),
        passphrase: @passphrase
      }
    end
  end
end
