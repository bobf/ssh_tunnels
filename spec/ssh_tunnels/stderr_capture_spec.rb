# frozen_string_literal: true

require 'tempfile'

RSpec.describe SshTunnels::StderrCapture do
  subject(:capture) { described_class.new(stream) }

  let(:file) { Tempfile.new('stderr') }
  let(:stream) { File.open(file.path, 'w') }

  after do
    capture.stop
    stream.close
    file.close!
  end

  def wait_for_output
    deadline = Time.now + 2
    sleep 0.01 while capture.empty? && Time.now < deadline
    sleep 0.05
  end

  it 'captures output written to the stream' do
    capture.start
    stream.puts("boom (RuntimeError)\n\tfrom a.rb:1:in 'x'")
    wait_for_output

    expect(capture.lines(80)).to eq(['boom (RuntimeError)', "    from a.rb:1:in 'x'"])
    expect(File.read(file.path)).to eq('')
  end

  it 'wraps lines longer than the given width' do
    capture.start
    stream.puts('abcdefghij')
    wait_for_output

    expect(capture.lines(4)).to eq(%w[abcd efgh ij])
  end

  it 'discards captured output when cleared' do
    capture.start
    stream.puts('boom')
    wait_for_output
    capture.clear

    expect(capture).to be_empty
  end

  it 'replaces earlier output after a quiet period' do
    stub_const("#{described_class}::QUIET_PERIOD", 0.1)
    capture.start
    stream.puts('first')
    wait_for_output
    sleep 0.2
    stream.puts('second')
    sleep 0.1

    expect(capture.lines(80)).to eq(['second'])
  end

  it 'restores the stream when stopped' do
    capture.start
    capture.stop
    stream.puts('after')
    stream.flush

    expect(File.read(file.path)).to eq("after\n")
  end
end
