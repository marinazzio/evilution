# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "rspec/core"
require "evilution/integration/rspec"

# EV-m6xc / GH #1627: RSpec redirects its own output to the streams it is handed
# only when the stream its configuration already holds is the current `$stdout`.
# In-process isolation swaps `$stdout` for a null IO around every mutation, and
# `--preload` builds the configuration before that swap — the project's
# spec_helper calls RSpec.configure — so the two no longer match and the run's
# output lands on the real stdout, ahead of the report.
#
# The run therefore claims the configuration's streams rather than offering
# them. These examples drive the integration with a stubbed runner, the way the
# host-isolation specs do: a real run would clear RSpec's world and take the
# surrounding suite's pending examples with it.
RSpec.describe "Evilution::Integration::RSpec stream capture" do
  let(:config) { RSpec.configuration }
  let(:host_stream) { StringIO.new }

  def guarded_ivars
    %i[@output_stream @error_stream @reporter @formatter_loader]
  end

  # The integration restores what it found, but these examples set the host's
  # streams themselves, so they put the suite's own back.
  around do |example|
    saved = guarded_ivars.each_with_object({}) do |ivar, acc|
      acc[ivar] = config.instance_variable_get(ivar) if config.instance_variable_defined?(ivar)
    end
    example.run
  ensure
    guarded_ivars.each { |ivar| config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar) }
    saved.each { |ivar, value| config.instance_variable_set(ivar, value) }
  end

  before do
    allow(config).to receive(:add_formatter)
    # Stands in for the configuration a preloaded spec_helper leaves behind,
    # built while `$stdout` was still the real one.
    config.instance_variable_set(:@output_stream, host_stream)
    config.instance_variable_set(:@error_stream, host_stream)
  end

  def integration
    Evilution::Integration::RSpec.new(test_files: ["spec/nonexistent_spec.rb"])
  end

  def mutation
    instance_double(Evilution::Mutation, file_path: "lib/foo.rb", original_source: "class Foo\nend\n", line: 1)
  end

  # Stands in for RSpec's formatters, which write to whatever stream the
  # configuration holds when the run starts.
  def stub_run_writing_to_configured_stream(status: 0)
    allow(RSpec::Core::Runner).to receive(:run) do |_args, _err, _out|
      config.instance_variable_get(:@output_stream).write("run output")
      status
    end
  end

  it "keeps the run's output off the stream the host configured" do
    stub_run_writing_to_configured_stream
    instance = integration
    allow(instance).to receive(:reset_examples)

    instance.send(:run_tests, mutation)

    expect(host_stream.string).to eq("")
  end

  it "points the configuration at a stream of its own for the run" do
    captured = nil
    allow(RSpec::Core::Runner).to receive(:run) do |_args, _err, _out|
      captured = config.instance_variable_get(:@output_stream)
      0
    end
    instance = integration
    allow(instance).to receive(:reset_examples)

    instance.send(:run_tests, mutation)

    expect(captured).to be_a(StringIO).and(satisfy { |stream| !stream.equal?(host_stream) })
  end

  # A reporter built earlier holds the stream it was built with, so setting the
  # stream ivars alone would not have been enough.
  it "drops a reporter the host had already built" do
    config.instance_variable_set(:@reporter, Object.new)
    seen = :not_set
    allow(RSpec::Core::Runner).to receive(:run) do |_args, _err, _out|
      seen = config.instance_variable_defined?(:@reporter)
      0
    end
    instance = integration
    allow(instance).to receive(:reset_examples)

    instance.send(:run_tests, mutation)

    expect(seen).to be(false)
  end

  it "gives the host its streams back afterwards" do
    stub_run_writing_to_configured_stream
    instance = integration
    allow(instance).to receive(:reset_examples)

    instance.send(:run_tests, mutation)

    expect(config.instance_variable_get(:@output_stream)).to be(host_stream)
  end

  it "reports the run's verdict" do
    stub_run_writing_to_configured_stream(status: 1)
    instance = integration
    allow(instance).to receive(:reset_examples)

    expect(instance.send(:run_tests, mutation)[:passed]).to be(false)
  end
end
