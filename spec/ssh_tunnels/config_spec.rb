# frozen_string_literal: true

require 'tmpdir'

RSpec.describe SshTunnels::Config do
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, 'config.yml') }

  after { FileUtils.remove_entry(dir) }

  def write(content)
    File.write(path, content)
  end

  def load
    described_class.load(path)
  end

  describe '.load' do
    it 'raises when the file is missing' do
      expect { load }.to raise_error(SshTunnels::ConfigError, /Unable to locate/)
    end

    it 'raises on invalid YAML' do
      write("tunnels:\n  db: [unclosed")
      expect { load }.to raise_error(SshTunnels::ConfigError, /Invalid YAML/)
    end

    it 'raises when the document is not a map' do
      write('- just a list')
      expect { load }.to raise_error(SshTunnels::ConfigError, /YAML map/)
    end

    it 'raises when the tunnels section is missing' do
      write("default_gateway:\n  host: gw\n")
      expect { load }.to raise_error(SshTunnels::ConfigError, /`tunnels` section/)
    end

    it 'raises when a tunnel is not a map' do
      write("default_gateway:\n  host: gw\ntunnels:\n  db:\n")
      expect { load }.to raise_error(SshTunnels::ConfigError, /`db` must be a map/)
    end

    it 'raises when a tunnel lacks required keys' do
      write("default_gateway:\n  host: gw\ntunnels:\n  db:\n    host: db.internal\n")
      expect { load }.to raise_error(SshTunnels::ConfigError, /`db` must provide `remote_port`/)
    end

    it 'raises when a tunnel references an unknown gateway' do
      write("tunnels:\n  db:\n    host: db.internal\n    remote_port: 5432\n    gateway: nope\n")
      expect { load }.to raise_error(SshTunnels::ConfigError, /unknown gateway `nope`/)
    end

    it 'raises when a tunnel has no gateway and no default gateway exists' do
      write("tunnels:\n  db:\n    host: db.internal\n    remote_port: 5432\n")
      expect { load }.to raise_error(SshTunnels::ConfigError, /`default_gateway`/)
    end

    it 'reports every error at once' do
      write("tunnels:\n  a:\n    host: x\n  b:\n    remote_port: 1\n")
      expect { load }.to raise_error(SshTunnels::ConfigError) { |e| expect(e.message.lines.size).to eq(4) }
    end
  end

  describe '#tunnels' do
    before do
      write(<<~YAML)
        default_local_ip: 0.0.0.0
        default_gateway:
          host: gw.example.com
        gateways:
          aws:
            host: 1.2.3.4
            user: ubuntu
        tunnels:
          db:
            host: db.internal
            remote_port: 5432
          web:
            gateway: aws
            host: web.internal
            remote_port: 80
            local_port: 8080
            local_ip: 127.0.0.2
      YAML
    end

    it 'builds one tunnel per entry, in file order' do
      expect(load.tunnels('bob', 'secret').map(&:name)).to eq(%w[db web])
    end

    it 'resolves the default gateway and default local IP' do
      db = load.tunnels('bob', 'secret').first
      expect(db.gateway).to eq('host' => 'gw.example.com')
      expect(db.config).to eq('local_ip' => '0.0.0.0', 'host' => 'db.internal', 'remote_port' => 5432)
    end

    it 'resolves a named gateway and lets a tunnel override the local IP' do
      web = load.tunnels('bob', 'secret').last
      expect(web.gateway).to eq('host' => '1.2.3.4', 'user' => 'ubuntu')
      expect(web.config['local_ip']).to eq('127.0.0.2')
      expect(web.to_s).to eq('127.0.0.2:8080:web.internal:80')
    end
  end

  describe '#mtime' do
    it 'returns the file modification time' do
      write("default_gateway:\n  host: gw\ntunnels: {}\n")
      expect(load.mtime).to eq(File.mtime(path))
    end

    it 'returns nil once the file has been deleted' do
      write("default_gateway:\n  host: gw\ntunnels: {}\n")
      config = load
      File.delete(path)
      expect(config.mtime).to be_nil
    end
  end
end
