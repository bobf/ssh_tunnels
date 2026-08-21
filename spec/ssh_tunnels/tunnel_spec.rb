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
