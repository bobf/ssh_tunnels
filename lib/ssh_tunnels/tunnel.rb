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
      @gateway = gateway
      @session = nil
      @thread = nil
      @active = false
    end

    def to_s
      base = if local_host
               "#{local_host}:#{local_port}:#{remote_host}:#{remote_port}"
             else
               "#{local_port}:#{remote_host}:#{remote_port}"
             end
      return base unless @error

      "#{base} (#{@error})"
    end

    def toggle
      active? ? shutdown : open
    end

    def open
      @session = Net::SSH.start(@gateway.fetch('host'), @gateway.fetch('user', @user), options)
      if local_host
        @session.forward.local(local_host, local_port, remote_host, remote_port)
      else
        @session.forward.local(local_port, remote_host, remote_port)
      end
      @active = true
      @thread = Thread.new { @session.loop(0.001) { @active } }
    rescue StandardError
      shutdown
      raise
    end

    def active?
      @active && @thread&.alive?
    end

    def shutdown
      @active = false
      @thread&.join
      @session&.close
      @session = nil
      @thread = nil
    end

    private

    def remote_host
      @config.fetch('host')
    end

    def remote_port
      @config.fetch('remote_port')
    end

    def local_host
      @config.fetch('local_ip', nil)
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
