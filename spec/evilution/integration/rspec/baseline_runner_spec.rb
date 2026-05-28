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

  # Regression for EV-pyx6 / GH #1290: see FrameworkLoader#add_spec_load_path
  # for context. Under EV-wqxu sandbox CWD the baseline path needs the same
  # anchoring or the baseline rspec invocation cannot find spec_helper.
  describe "isolated-worker spec/ anchoring" do
    let(:project_spec_dir) { File.expand_path("spec", Evilution::PROJECT_ROOT) }

    around do |example|
      previous_flag = Evilution.instance_variable_get(:@in_isolated_worker)
      load_path_before = $LOAD_PATH.dup
      example.run
    ensure
      Evilution.instance_variable_set(:@in_isolated_worker, previous_flag)
      $LOAD_PATH.replace(load_path_before)
    end

    it "anchors spec/ to Evilution::PROJECT_ROOT (not sandbox CWD) inside an isolated worker" do
      Dir.mktmpdir do |sandbox|
        sandbox_spec_dir = File.expand_path("spec", sandbox)
        Dir.chdir(sandbox) do
          Evilution.in_isolated_worker!

          runner.call("spec/foo_spec.rb")

          expect($LOAD_PATH).to include(project_spec_dir)
          expect($LOAD_PATH).not_to include(sandbox_spec_dir)
        end
      end
    end

    it "anchors spec/ to Dir.pwd when the isolated-worker flag is unset" do
      Dir.mktmpdir do |sandbox|
        sandbox_spec_dir = File.expand_path("spec", sandbox)
        Dir.chdir(sandbox) do
          runner.call("spec/foo_spec.rb")

          expect($LOAD_PATH).to include(sandbox_spec_dir)
        end
      end
    end
  end
end
