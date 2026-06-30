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
      @error = nil
      connect
      @active = true
      @thread = Thread.new { run_loop }
    rescue StandardError => e
      @error = e
      @active = false
      @session&.close
      @session = nil
      raise
    end

    def active?
      @active && @thread&.alive?
    end

    def shutdown
      @active = false
      @thread&.join
      @thread = nil
      @session = nil
    end

    private

    def connect
      @session = Net::SSH.start(@gateway.fetch('host'), @gateway.fetch('user', @user), options)
      forward_local
    end

    # Runs in the background thread. When the loop ends — whether because the
    # user disconnected (@active set to false) or the connection dropped (the
    # loop raises) — we must close the session here so the local forwarded port
    # is released. Otherwise the orphaned listener keeps the port bound, causing
    # connecting apps to hang and reconnects to fail with "address in use".
    def run_loop
      @session.loop(0.001) { @active }
    rescue StandardError => e
      @error = e
    ensure
      @active = false
      @session&.close
      @session = nil
    end

    def forward_local
      args = [local_port, remote_host, remote_port]
      args.unshift(local_host) if local_host
      @session.forward.local(*args)
    end

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
