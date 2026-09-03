# frozen_string_literal: true

module SshTunnels
  # rubocop:disable Metrics/ClassLength
  # SSH Tunnel
  class Tunnel
    attr_reader :name, :error, :config, :gateway

    # Merges freshly-loaded tunnels into the current list. Tunnels that share a
    # name keep their existing object (and therefore any live connection) and
    # receive the new settings via #update. Tunnels no longer present in the
    # configuration are dropped if inactive, or kept and flagged as removed
    # while still connected so a file edit never interrupts a live session.
    def self.reconcile(current, incoming)
      existing = current.to_h { |tunnel| [tunnel.name, tunnel] }
      merged = incoming.map do |tunnel|
        match = existing.delete(tunnel.name)
        next tunnel if match.nil?

        match.update(tunnel.config, tunnel.gateway)
        match
      end
      merged + existing.values.select(&:active?).each(&:remove)
    end

    def initialize(name, user, config, gateway, passphrase)
      @name = name
      @user = user
      @config = config
      @passphrase = passphrase
      @gateway = gateway
      @session = nil
      @thread = nil
      @active = false
      @pending = nil
      @removed = false
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

    # Called on configuration reload. Inactive tunnels take the new settings
    # immediately; active tunnels keep running on their current settings and
    # apply the new ones when next disconnected.
    def update(config, gateway)
      @removed = false
      if config == @config && gateway == @gateway
        @pending = nil
      elsif active?
        @pending = [config, gateway]
      else
        apply(config, gateway)
      end
    end

    def remove
      @removed = true
    end

    def removed?
      @removed
    end

    def changed?
      !@pending.nil?
    end

    def toggle
      active? ? shutdown : open
    end

    def open
      apply_pending
      @error = nil
      connect
      @active = true
      @thread = Thread.new { run_loop }
    rescue StandardError => e
      @error = e
      @active = false
      close_session
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
      apply_pending
    end

    private

    def apply_pending
      apply(*@pending) unless @pending.nil?
    end

    def apply(config, gateway)
      @config = config
      @gateway = gateway
      @pending = nil
      @error = nil
    end

    def connect
      @session = Net::SSH.start(@gateway.fetch('host'), @gateway.fetch('user', @user), options)
      forward_local
    end

    # Runs in the background thread. When the loop ends — whether because the
    # user disconnected (@active set to false) or the connection dropped (the
    # loop raises) — the local forwarded port must be released here. Otherwise
    # the orphaned listener keeps the port bound, causing connecting apps to
    # hang and reconnects to fail with "address in use".
    def run_loop
      @session.loop(0.001) { @active }
    rescue StandardError => e
      @error = e
    ensure
      @active = false
      close_session
    end

    # Net::SSH::Connection::Session#close only closes channels and the
    # transport socket; the TCPServer bound by forward.local is only released
    # by forward.cancel_local, so cancel before closing.
    def close_session
      release_port
      @session&.close
      @session = nil
    end

    def release_port
      return if @session.nil?

      args = [local_port]
      args << local_host if local_host
      @session.forward.cancel_local(*args)
    rescue StandardError
      nil
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
  # rubocop:enable Metrics/ClassLength
end
