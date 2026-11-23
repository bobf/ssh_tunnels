# frozen_string_literal: true

module SshTunnels
  # Captures everything written to the standard error stream while the curses
  # screen is active. Output written straight to the terminal in that mode
  # appears without line breaks and corrupts the display, so the stream is
  # redirected into a pipe and the text is kept for the UI to draw.
  #
  # Only one block of output is retained: output arriving after a quiet period
  # replaces whatever was captured before.
  class StderrCapture
    QUIET_PERIOD = 2
    LIMIT = 64 * 1024
    TAB = ' ' * 4

    def initialize(stream = $stderr)
      @stream = stream
      @mutex = Mutex.new
      @text = +''
      @updated_at = nil
      @original = nil
    end

    # Redirection happens at the file descriptor level so that output from
    # loggers and background threads holding a reference to the stream is
    # captured too.
    def start
      return unless @original.nil?

      @original = @stream.dup
      @reader, writer = IO.pipe
      @stream.reopen(writer)
      @stream.sync = true
      writer.close
      @thread = Thread.new { drain }
    end

    def stop
      return if @original.nil?

      @stream.reopen(@original)
      @stream.sync = true
      @original.close
      @original = nil
      @thread.join
      @reader.close
    end

    def empty?
      @mutex.synchronize { @text.empty? }
    end

    def clear
      @mutex.synchronize { @text = +'' }
    end

    # Captured text as display lines no wider than +width+.
    def lines(width)
      text = @mutex.synchronize { @text.dup }
      text.force_encoding(Encoding::UTF_8).scrub('?').split(/\r?\n/).flat_map do |line|
        line = line.gsub("\t", TAB).gsub(/[^[:print:]]/, '')
        line.empty? ? [line] : line.scan(/.{1,#{width}}/)
      end
    end

    private

    def drain
      loop { append(@reader.readpartial(4096)) }
    rescue IOError
      nil
    end

    def append(chunk)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @mutex.synchronize do
        @text = +'' if @updated_at && now - @updated_at > QUIET_PERIOD
        @updated_at = now
        @text << chunk.byteslice(0, LIMIT - @text.bytesize).to_s
      end
    end
  end
end
