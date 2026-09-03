# frozen_string_literal: true

require 'timeout'

# Fake net-ssh forwarder backed by a shared `bound_ports` array that stands in
# for the OS port table: binding an already-bound port raises EADDRINUSE, just
# as the real local forward does. This lets us reproduce the original bug where
# a dropped tunnel left its local port bound and blocked reconnection.
class FakeForward
  def initialize(session)
    @session = session
    @registered = []
  end

  def local(local_port, *_rest)
    raise Errno::EADDRINUSE, local_port.to_s if @session.bound_ports.include?(local_port)

    @session.bound_ports << local_port
    @registered << local_port
    @session.bound_port = local_port
  end

  # Only releases ports this forwarder bound itself, mirroring the real
  # cancel_local, which only closes sockets in @local_forwarded_ports.
  def cancel_local(local_port, _bind_address = '127.0.0.1')
    return unless @registered.delete(local_port)

    @session.bound_ports.delete(local_port)
  end
end

# Fake net-ssh session. `loop_behavior: :raise` simulates the connection
# dropping mid-loop; `:clean` runs until the tunnel sets @active to false.
# Like the real Net::SSH session, `close` does NOT release forwarded ports —
# only `forward.cancel_local` does.
class FakeSession
  attr_accessor :bound_port
  attr_reader :bound_ports, :closed

  def initialize(loop_behavior:, bound_ports:)
    @loop_behavior = loop_behavior
    @bound_ports = bound_ports
    @closed = false
  end

  def forward
    @forward ||= FakeForward.new(self)
  end

  def loop(_interval)
    raise Net::SSH::Disconnect, 'connection lost' if @loop_behavior == :raise

    sleep(0.001) while yield
  end

  def close
    @closed = true
  end
end

RSpec.describe SshTunnels::Tunnel do
  subject(:tunnel) { described_class.new('postgres', 'bob', config, gateway, 'secret') }

  let(:config) { { 'host' => 'db.internal', 'remote_port' => 5432, 'local_port' => 6000 } }
  let(:gateway) { { 'host' => 'gateway.example.com', 'user' => 'deploy' } }
  let(:bound_ports) { [] }

  let(:failing_session) { FakeSession.new(loop_behavior: :raise, bound_ports: bound_ports) }
  let(:healthy_session) { FakeSession.new(loop_behavior: :clean, bound_ports: bound_ports) }

  def wait_for
    Timeout.timeout(2) { sleep(0.001) until yield }
  end

  describe 'connection drop' do
    before { allow(Net::SSH).to receive(:start).and_return(failing_session) }

    it 'releases the local port so the session no longer holds it' do
      tunnel.open
      wait_for { failing_session.closed }

      expect(failing_session.closed).to be(true)
      expect(bound_ports).to be_empty
    end

    it 'records the error and reports itself inactive' do
      tunnel.open
      wait_for { failing_session.closed }

      expect(tunnel.error).to be_a(Net::SSH::Disconnect)
      expect(tunnel.active?).to be(false)
    end
  end

  describe 'reconnecting after a drop' do
    before { allow(Net::SSH).to receive(:start).and_return(failing_session, healthy_session) }

    it 'reconnects without a port conflict and clears the previous error' do
      tunnel.open
      wait_for { failing_session.closed }

      expect { tunnel.open }.not_to raise_error
      expect(tunnel.active?).to be(true)
      expect(tunnel.error).to be_nil

      tunnel.shutdown
    end
  end

  describe 'normal shutdown' do
    before { allow(Net::SSH).to receive(:start).and_return(healthy_session) }

    it 'closes the session, frees the port, and records no error' do
      tunnel.open
      expect(tunnel.active?).to be(true)

      tunnel.shutdown

      expect(healthy_session.closed).to be(true)
      expect(bound_ports).to be_empty
      expect(tunnel.error).to be_nil
      expect(tunnel.active?).to be(false)
    end

    it 'can reconnect after a deliberate disconnect' do
      tunnel.open
      tunnel.shutdown

      expect { tunnel.open }.not_to raise_error
      expect(tunnel.active?).to be(true)

      tunnel.shutdown
    end
  end

  describe 'failure while establishing the tunnel' do
    before do
      bound_ports << 6000 # local port already taken by something else
      allow(Net::SSH).to receive(:start).and_return(failing_session)
    end

    it 'closes the session, records the error, and re-raises' do
      expect { tunnel.open }.to raise_error(Errno::EADDRINUSE)

      expect(failing_session.closed).to be(true)
      expect(tunnel.error).to be_a(Errno::EADDRINUSE)
      expect(tunnel.active?).to be(false)
      expect(bound_ports).to eq([6000]) # the pre-existing binding is left untouched
    end
  end
end

RSpec.describe SshTunnels::Tunnel, 'configuration reload' do
  subject(:tunnel) { described_class.new('postgres', 'bob', config, gateway, 'secret') }

  let(:config) { { 'host' => 'db.internal', 'remote_port' => 5432, 'local_port' => 6000 } }
  let(:gateway) { { 'host' => 'gateway.example.com', 'user' => 'deploy' } }
  let(:new_config) { config.merge('local_port' => 7000) }
  let(:bound_ports) { [] }
  let(:session) { FakeSession.new(loop_behavior: :clean, bound_ports: bound_ports) }

  before { allow(Net::SSH).to receive(:start).and_return(session) }

  def build(name, config: self.config, gateway: self.gateway)
    described_class.new(name, 'bob', config, gateway, 'secret')
  end

  describe '#update' do
    it 'applies new settings immediately while disconnected' do
      tunnel.update(new_config, gateway)

      expect(tunnel.config).to eq(new_config)
      expect(tunnel.changed?).to be(false)
    end

    it 'defers new settings while connected and applies them on disconnect' do
      tunnel.open
      tunnel.update(new_config, gateway)

      expect(tunnel.config).to eq(config)
      expect(tunnel.changed?).to be(true)

      tunnel.shutdown

      expect(tunnel.config).to eq(new_config)
      expect(tunnel.changed?).to be(false)
    end

    it 'applies deferred settings when reconnecting after the connection dropped' do
      tunnel.open
      tunnel.update(new_config, gateway)
      tunnel.instance_variable_set(:@active, false) # simulate the run loop ending on its own
      tunnel.instance_variable_get(:@thread).join

      tunnel.open
      expect(tunnel.config).to eq(new_config)
      tunnel.shutdown
    end

    it 'drops a pending change if the settings are reverted before disconnecting' do
      tunnel.open
      tunnel.update(new_config, gateway)
      tunnel.update(config, gateway)

      expect(tunnel.changed?).to be(false)
      tunnel.shutdown
      expect(tunnel.config).to eq(config)
    end

    it 'clears the removed flag' do
      tunnel.remove
      tunnel.update(config, gateway)

      expect(tunnel.removed?).to be(false)
    end
  end

  describe '.reconcile' do
    it 'keeps the existing object for a tunnel that is still configured' do
      current = [tunnel]
      result = described_class.reconcile(current, [build('postgres', config: new_config)])

      expect(result).to eq([tunnel])
      expect(tunnel.config).to eq(new_config)
    end

    it 'adds new tunnels and drops inactive removed ones, in configuration order' do
      redis = build('redis')
      result = described_class.reconcile([tunnel], [redis, build('postgres')])

      expect(result.map(&:name)).to eq(%w[redis postgres])
      expect(result.last).to equal(tunnel)
    end

    it 'keeps a removed tunnel that is still connected and flags it' do
      tunnel.open
      result = described_class.reconcile([tunnel], [build('redis')])

      expect(result.map(&:name)).to eq(%w[redis postgres])
      expect(tunnel.removed?).to be(true)
      expect(tunnel.active?).to be(true)
      tunnel.shutdown
    end

    it 'un-flags a removed tunnel that reappears in the configuration' do
      tunnel.open
      described_class.reconcile([tunnel], [])
      result = described_class.reconcile([tunnel], [build('postgres')])

      expect(result).to eq([tunnel])
      expect(tunnel.removed?).to be(false)
      tunnel.shutdown
    end
  end
end
