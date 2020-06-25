# frozen_string_literal: true

module SshTunnels
  # rubocop:disable Metrics/ClassLength
  # User Interface
  class UI
    def initialize(tunnels)
      @tunnels = tunnels
    end

    def setup
      Curses.init_screen
      Curses.start_color
      Curses.init_pair(1, Curses::COLOR_WHITE, Curses::COLOR_BLACK)
      Curses.init_pair(2, Curses::COLOR_BLUE, Curses::COLOR_BLACK)
      Curses.init_pair(3, Curses::COLOR_GREEN, Curses::COLOR_BLACK)
      Curses.init_pair(4, Curses::COLOR_CYAN, Curses::COLOR_BLACK)
      Curses.init_pair(5, Curses::COLOR_RED, Curses::COLOR_BLACK)
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

    def window
      @window ||= Curses.stdscr
    end

    # rubocop:disable Metrics/AbcSize
    def display_tunnel(tunnel, index)
      window.setpos(index + 2, 2)
      window.attrset(color(:white))
      window.addstr("#{index + 1}. ")
      window.attrset(tunnel_color(tunnel))
      window.addstr("#{tunnel.name} ")
      window.attrset(color(:cyan))
      window.addstr(tunnel.to_s)
    end
    # rubocop:enable Metrics/AbcSize

    def display_usage
      window.setpos(@tunnels.size + 3, 2)
      window.attrset(color(:cyan))
      message = "[1-#{@tunnels.size}] to connect/disconnect. Press 'q' to quit."
      window.addstr(message)
    end

    def process_input(input)
      raise UserQuit if input == 'q'
      return status("Unrecognized input: #{input}") unless input.is_a?(String) && input =~ /\A\d+\Z/

      tunnel = @tunnels[input.to_i - 1]
      return status("Unrecognized tunnel: #{input}") if tunnel.nil?

      if tunnel.active?
        status("Disconnecting: #{tunnel}")
      else
        status("Connecting: #{tunnel}")
      end
      tunnel.toggle
    end

    def tunnel_color(tunnel)
      return color(:red) if tunnel.error

      tunnel.active? ? color(:green) : color(:blue)
    end

    def status(message)
      clean_status
      @status_time = Time.now.utc
      window.setpos(*status_coordinates)
      window.attrset(color(:white))
      window.addstr(message)
      window.refresh
    end

    def clean_status
      y, x = status_coordinates
      window.setpos(y, x)
      window.attrset(color(:white))
      window.addstr(' ' * (Curses.cols - x))
    end

    def status_coordinates
      [@tunnels.size + 5, 2]
    end

    def color(name)
      Curses.color_pair(
        {
          white: 1,
          blue: 2,
          green: 3,
          cyan: 4,
          red: 5
        }.fetch(name)
      )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
