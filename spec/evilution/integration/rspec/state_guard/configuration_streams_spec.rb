# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "rspec/core"
require "evilution/integration/rspec/state_guard/configuration_streams"

RSpec.describe Evilution::Integration::RSpec::StateGuard::ConfigurationStreams do
  let(:strategy) { described_class.new }
  let(:config) { RSpec.configuration }

  def guarded_ivars
    %i[@color_mode @output_stream @error_stream]
  end

  # Guard the host's real configuration: capture and restore around each
  # example so mutating these singleton ivars can't leak into the suite.
  around do |example|
    saved = guarded_ivars.each_with_object({}) do |iv, acc|
      acc[iv] = config.instance_variable_get(iv) if config.instance_variable_defined?(iv)
    end
    example.run
  ensure
    guarded_ivars.each { |iv| config.remove_instance_variable(iv) if config.instance_variable_defined?(iv) }
    saved.each { |iv, value| config.instance_variable_set(iv, value) }
  end

  it "snapshot captures color_mode, output_stream and error_stream" do
    out = StringIO.new
    err = StringIO.new
    config.instance_variable_set(:@color_mode, :on)
    config.instance_variable_set(:@output_stream, out)
    config.instance_variable_set(:@error_stream, err)

    expect(strategy.snapshot).to eq(:@color_mode => :on, :@output_stream => out, :@error_stream => err)
  end

  it "release restores all three ivars after they are mutated" do
    orig_out = StringIO.new
    config.instance_variable_set(:@color_mode, :on)
    config.instance_variable_set(:@output_stream, orig_out)

    snap = strategy.snapshot
    config.instance_variable_set(:@color_mode, :off)
    config.instance_variable_set(:@output_stream, StringIO.new)

    strategy.release(snap)

    expect(config.instance_variable_get(:@color_mode)).to eq(:on)
    expect(config.instance_variable_get(:@output_stream)).to equal(orig_out)
  end

  it "restores via the ivar so the guarded output_stream= setter cannot block it" do
    # configuration#output_stream= warns and no-ops once @reporter is set; the
    # strategy must bypass it. Simulate a live reporter and confirm restore wins.
    orig_out = StringIO.new
    config.instance_variable_set(:@output_stream, orig_out)
    config.instance_variable_set(:@reporter, Object.new)
    snap = strategy.snapshot
    config.instance_variable_set(:@output_stream, StringIO.new)

    strategy.release(snap)

    expect(config.instance_variable_get(:@output_stream)).to equal(orig_out)
  ensure
    config.remove_instance_variable(:@reporter) if config.instance_variable_defined?(:@reporter)
  end

  it "release is a no-op when snapshot is nil" do
    expect { strategy.release(nil) }.not_to raise_error
  end

  it "snapshot omits ivars that are not defined" do
    guarded_ivars.each { |iv| config.remove_instance_variable(iv) if config.instance_variable_defined?(iv) }

    expect(strategy.snapshot).to eq({})
  end
end
