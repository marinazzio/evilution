# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/state_guard/reporter_arrays"

RSpec.describe Evilution::Integration::RSpec::StateGuard::ReporterArrays do
  let(:strategy) { described_class.new }
  let(:fake_reporter) do
    Class.new do
      def initialize
        @examples = []
        @failed_examples = []
        @pending_examples = []
      end

      attr_reader :examples, :failed_examples, :pending_examples
    end.new
  end

  before do
    @cfg_backup = if RSpec.configuration.instance_variable_defined?(:@reporter)
                    RSpec.configuration.instance_variable_get(:@reporter)
                  else
                    :__missing__
                  end
    RSpec.configuration.instance_variable_set(:@reporter, fake_reporter)
  end

  after do
    if @cfg_backup == :__missing__
      RSpec.configuration.remove_instance_variable(:@reporter) if RSpec.configuration.instance_variable_defined?(:@reporter)
    else
      RSpec.configuration.instance_variable_set(:@reporter, @cfg_backup)
    end
  end

  it "snapshot returns lengths of the three reporter arrays" do
    fake_reporter.examples.push(:e1, :e2)
    fake_reporter.failed_examples.push(:f1)
    snap = strategy.snapshot
    expect(snap).to eq({ :@examples => 2, :@failed_examples => 1, :@pending_examples => 0 })
  end

  it "release slices arrays back to snapshot lengths" do
    fake_reporter.examples.push(:pre)
    snap = strategy.snapshot
    fake_reporter.examples.push(:added_a, :added_b)

    strategy.release(snap)

    expect(fake_reporter.examples).to eq([:pre])
  end

  it "release is a no-op when snapshot is nil" do
    fake_reporter.examples.push(:a, :b)
    expect { strategy.release(nil) }.not_to raise_error
    expect(fake_reporter.examples).to eq(%i[a b])
  end

  it "snapshot returns nil when reporter ivar is missing" do
    RSpec.configuration.remove_instance_variable(:@reporter) if RSpec.configuration.instance_variable_defined?(:@reporter)
    expect(strategy.snapshot).to be_nil
  end

  it "snapshot omits ivars that are not defined on the reporter" do
    partial_reporter = Class.new do
      def initialize
        @examples = [:e1]
      end
      attr_reader :examples
    end.new
    RSpec.configuration.instance_variable_set(:@reporter, partial_reporter)

    snap = strategy.snapshot

    expect(snap).to eq({ :@examples => 1 })
  end

  it "snapshot skips ivars whose value is not an Array" do
    weird_reporter = Class.new do
      def initialize
        @examples = []
        @failed_examples = "not an array"
        @pending_examples = nil
      end
      attr_reader :examples, :failed_examples, :pending_examples
    end.new
    RSpec.configuration.instance_variable_set(:@reporter, weird_reporter)

    snap = strategy.snapshot

    expect(snap).to eq({ :@examples => 0 })
  end

  it "release is a no-op when reporter ivar is missing on RSpec.configuration" do
    fake_reporter.examples.push(:pre)
    snap = strategy.snapshot
    RSpec.configuration.remove_instance_variable(:@reporter) if RSpec.configuration.instance_variable_defined?(:@reporter)

    expect { strategy.release(snap) }.not_to raise_error
  end
end
