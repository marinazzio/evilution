# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/baseline_runner"

RSpec.describe Evilution::Integration::RSpec::BaselineRunner do
  let(:runner) { described_class.new }

  before do
    allow(RSpec).to receive(:reset)
    allow(RSpec::Core::Runner).to receive(:run).and_return(0)
  end

  it "calls RSpec::Core::Runner.run with --format progress --no-color --order defined args + spec file" do
    runner.call("spec/foo_spec.rb")
    expect(RSpec::Core::Runner).to have_received(:run)
      .with(["--format", "progress", "--no-color", "--order", "defined", "spec/foo_spec.rb"])
  end

  it "returns true when status is 0" do
    allow(RSpec::Core::Runner).to receive(:run).and_return(0)
    expect(runner.call("spec/foo_spec.rb")).to be true
  end

  it "returns false when status is non-zero" do
    allow(RSpec::Core::Runner).to receive(:run).and_return(1)
    expect(runner.call("spec/foo_spec.rb")).to be false
  end

  it "calls RSpec.reset before running" do
    runner.call("spec/foo_spec.rb")
    expect(RSpec).to have_received(:reset)
  end

  it "prepends spec/ to LOAD_PATH" do
    runner.call("spec/foo_spec.rb")
    expect($LOAD_PATH).to include(File.expand_path("spec"))
  end
end
