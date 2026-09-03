# frozen_string_literal: true

module SshTunnels
  # rubocop:disable Metrics/ClassLength
  # User Interface
  class UI
    IDENTIFIERS = ['1'..'9', 'a'..'z', 'A'..'Z'].map(&:to_a).flatten
    COLORS = {
      white: Curses::COLOR_WHITE,
      blue: Curses::COLOR_BLUE,
      green: Curses::COLOR_GREEN,
      cyan: Curses::COLOR_CYAN,
      red: Curses::COLOR_RED,
      yellow: Curses::COLOR_YELLOW
    }.freeze

    def initialize(config, user, passphrase)
      @config = config
      @user = user
      @passphrase = passphrase
      @tunnels = config.tunnels(user, passphrase)
      @config_mtime = config.mtime
    end

    def setup
      Curses.init_screen
      Curses.start_color
      COLORS.each_value.with_index(1) { |value, pair| Curses.init_pair(pair, value, Curses::COLOR_BLACK) }
      Curses.timeout = 1000
      Curses.curs_set(0)
      Curses.noecho
    end

    def run
      setup
      monitor
    rescue Net::SSH::Disconnect, Errno::ECONNRESET => e
      shutdown("Error encountered: #{e}")
    ensure
      Curses.close_screen
    end

    def shutdown(error = nil)
      Curses.close_screen
      puts error unless error.nil?
      puts 'Shutting down connections.'
      @tunnels.select(&:active?).each(&:shutdown)
      puts 'Shutdown complete.'
    end

    private

    def monitor
      loop do
        reload_if_changed
        prune_removed
        @tunnels.each_with_index do |tunnel, index|
          display_tunnel(tunnel, index)
        end
        refresh
      end
    rescue UserQuit
      shutdown
    end

    def refresh
      display_usage
      window.refresh
      input = window.getch
      process_input(input) unless input.nil?
      clean_status if @status_time && Time.now.utc - @status_time > 2.5
    end

    # The configuration file is polled once per tick (see Curses.timeout). A
    # change triggers a reload; an unreadable or invalid file leaves the
    # current tunnels untouched and reports the problem until the next
    # successful reload.
    def reload_if_changed
      mtime = @config.mtime
      return if mtime == @config_mtime

      @config_mtime = mtime
      reload
    end

    def reload
      @config = Config.load(@config.path)
      @tunnels = Tunnel.reconcile(@tunnels, @config.tunnels(@user, @passphrase))
      window.erase
      status('Configuration reloaded.')
    rescue ConfigError => e
      status("Configuration error: #{e.message.lines.first.chomp}", sticky: true)
    end

    # Tunnels removed from the configuration stay listed while connected and
    # disappear once they are no longer active.
    def prune_removed
      orphans = @tunnels.select { |tunnel| tunnel.removed? && !tunnel.active? }
      return if orphans.empty?

      @tunnels -= orphans
      window.erase
    end

    def window
      @window ||= Curses.stdscr
    end

    # rubocop:disable Metrics/AbcSize
    def display_tunnel(tunnel, index)
      window.setpos(index + 2, 2)
      window.attrset(color(:white))
      window.addstr("#{IDENTIFIERS[index]}. ")
      window.attrset(tunnel_color(tunnel))
      window.addstr("#{tunnel.name} ")
      window.attrset(color(:cyan))
      window.addstr(tunnel.to_s)
      display_marker(tunnel)
      window.clrtoeol
    end
    # rubocop:enable Metrics/AbcSize

    def display_marker(tunnel)
      marker = tunnel_marker(tunnel)
      return if marker.nil?

      window.attrset(color(:yellow))
      window.addstr(" [#{marker}]")
    end

    def tunnel_marker(tunnel)
      return 'removed from config, disconnect to clear' if tunnel.removed?
      return 'config changed, reconnect to apply' if tunnel.changed?

      nil
    end

    def display_usage
      window.setpos(@tunnels.size + 3, 2)
      window.attrset(color(:cyan))
      window.addstr(usage_message)
      window.clrtoeol
    end

    def usage_message
      return "No tunnels configured. Press 'q' to quit." if @tunnels.empty?

      "[1-#{IDENTIFIERS[@tunnels.size - 1]}] to connect/disconnect. Press 'q' to quit."
    end

    def process_input(input)
      raise UserQuit if input == 'q'
      return status("Unrecognized input: #{input}") unless input.is_a?(String) && input =~ /\A[0-9a-zA-Z]\Z/

      index = IDENTIFIERS.index(input)
      tunnel = index && @tunnels[index]
      return status("Unrecognized tunnel: #{input}") if tunnel.nil?

      toggle_tunnel(tunnel)
    end

    def toggle_tunnel(tunnel)
      status("#{tunnel.active? ? 'Disconnecting' : 'Connecting'}: #{tunnel}")
      tunnel.toggle
    rescue StandardError => e
      status("Error: #{e}")
    end

    def tunnel_color(tunnel)
      return color(:red) if tunnel.error

      tunnel.active? ? color(:green) : color(:blue)
    end

    # A sticky status stays until replaced by the next status message rather
    # than being cleared after a few seconds.
    def status(message, sticky: false)
      clean_status
      @status_time = sticky ? nil : Time.now.utc
      window.setpos(*status_coordinates)
      window.attrset(color(:white))
      window.addstr(message)
      window.refresh
    end

    def clean_status
      y, x = status_coordinates
      window.setpos(y, x)
      window.attrset(color(:white))
      window.clrtoeol
    end

    def status_coordinates
      [@tunnels.size + 5, 2]
    end

    def color(name)
      Curses.color_pair(COLORS.keys.index(name) + 1)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
