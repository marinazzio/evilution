# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "evilution/integration/rspec/state_guard/configuration_state"

RSpec.describe Evilution::Integration::RSpec::StateGuard::ConfigurationState do
  # A bare stand-in for RSpec.configuration: the strategy only uses ivar
  # operations, so a plain object isolates these tests from the real singleton
  # (mutating the real one mid-suite breaks RSpec's own reporting).
  let(:config) { Object.new }
  let(:strategy) { described_class.new(configuration: config) }

  def set_ivars(preferred: nil, out: nil, err: nil)
    config.instance_variable_set(:@preferred_options, preferred) unless preferred.nil?
    config.instance_variable_set(:@output_stream, out) unless out.nil?
    config.instance_variable_set(:@error_stream, err) unless err.nil?
  end

  describe "#snapshot" do
    it "captures preferred_options as a copy, plus the stream ivars" do
      out = StringIO.new
      err = StringIO.new
      set_ivars(preferred: { color_mode: :on }, out: out, err: err)

      snap = strategy.snapshot

      expect(snap[:@preferred_options]).to eq(color_mode: :on)
      expect(snap[:@output_stream]).to equal(out)
      expect(snap[:@error_stream]).to equal(err)
    end

    it "copies preferred_options so a later in-place mutation does not change the snapshot" do
      set_ivars(preferred: { color_mode: :on })

      snap = strategy.snapshot
      config.instance_variable_get(:@preferred_options)[:color_mode] = :off

      expect(snap[:@preferred_options]).to eq(color_mode: :on)
    end

    it "omits ivars that are not defined" do
      expect(strategy.snapshot).to eq({})
    end
  end

  describe "#release" do
    it "restores preferred_options after an in-place merge (the color leak)" do
      set_ivars(preferred: { color_mode: :on })

      snap = strategy.snapshot
      # Simulate Configuration#force from the inner run's --no-color.
      config.instance_variable_get(:@preferred_options).merge!(color_mode: :off)

      strategy.release(snap)

      expect(config.instance_variable_get(:@preferred_options)).to eq(color_mode: :on)
    end

    it "restores the output and error streams" do
      orig_out = StringIO.new
      orig_err = StringIO.new
      set_ivars(preferred: {}, out: orig_out, err: orig_err)

      snap = strategy.snapshot
      config.instance_variable_set(:@output_stream, StringIO.new)
      config.instance_variable_set(:@error_stream, StringIO.new)

      strategy.release(snap)

      expect(config.instance_variable_get(:@output_stream)).to equal(orig_out)
      expect(config.instance_variable_get(:@error_stream)).to equal(orig_err)
    end

    it "removes an ivar that was undefined before the run but created during it" do
      snap = strategy.snapshot # {} -- nothing defined
      config.instance_variable_set(:@output_stream, StringIO.new) # created "during the run"

      strategy.release(snap)

      expect(config.instance_variable_defined?(:@output_stream)).to be(false)
    end

    it "is a no-op when snapshot is nil" do
      expect { strategy.release(nil) }.not_to raise_error
    end
  end
end
