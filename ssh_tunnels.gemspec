# frozen_string_literal: true

require_relative 'lib/ssh_tunnels/version'

Gem::Specification.new do |spec|
  spec.name          = 'ssh_tunnels'
  spec.version       = SshTunnels::VERSION
  spec.authors       = ['Bob Farrell']
  spec.email         = ['git@bob.frl']

  spec.summary       = 'Interactive SSH tunnel management'
  spec.description   = 'Conveniently manage numerous SSH tunnels with ncurses'
  spec.homepage      = 'https://github.com/bobf/ssh_tunnels'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.3.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = 'https://github.com/bobf/ssh_tunnels/blob/master/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'bin'
  spec.executables   = 'ssh_tunnels'
  spec.require_paths = ['lib']

  spec.add_dependency 'bcrypt_pbkdf', '~> 1.1'
  spec.add_dependency 'curses', '~> 1.4'
  spec.add_dependency 'ed25519', '~> 1.3'
  spec.add_dependency 'net-ssh', '~> 7.0'
end
