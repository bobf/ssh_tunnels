# frozen_string_literal: true

require 'curses'
require 'net/ssh/gateway'

require 'ssh_tunnels/version'
require 'ssh_tunnels/tunnel'
require 'ssh_tunnels/ui'

module SshTunnels
  class Error < StandardError; end
  class UserQuit < Error; end
end
