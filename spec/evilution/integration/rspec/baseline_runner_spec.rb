# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "json"
require "open3"
require "tmpdir"
require "fileutils"
require "evilution/baseline"
require "evilution/integration/rspec/baseline_runner"

RSpec.describe Evilution::Integration::RSpec::BaselineRunner do
  let(:runner) { described_class.new }

  before do
    allow(RSpec).to receive(:clear_examples)
    allow(RSpec).to receive(:reset)
    allow(RSpec::Core::Runner).to receive(:run).and_return(0)
  end

  it "calls RSpec::Core::Runner.run with --format progress --no-color --order defined args + spec file" do
    runner.call("spec/foo_spec.rb")
    expect(RSpec::Core::Runner).to have_received(:run)
      .with(["--format", "progress", "--no-color", "--order", "defined", "spec/foo_spec.rb"],
            an_instance_of(StringIO), an_instance_of(StringIO))
  end

  it "reports a pass when status is 0" do
    allow(RSpec::Core::Runner).to receive(:run).and_return(0)
    expect(runner.call("spec/foo_spec.rb")).to eq(Evilution::Baseline::Report.build(passed: true))
  end

  it "reports a failure when status is non-zero" do
    allow(RSpec::Core::Runner).to receive(:run).and_return(1)
    expect(runner.call("spec/foo_spec.rb")[:passed]).to be false
  end

  # RSpec.reset throws the configuration away. A helper loaded by --preload is
  # not loaded again by the spec's own require, so its RSpec.configure block
  # never re-runs and the file goes red in the baseline alone.
  it "clears examples before running, keeping the configuration" do
    runner.call("spec/foo_spec.rb")
    expect(RSpec).to have_received(:clear_examples)
    expect(RSpec).not_to have_received(:reset)
  end

  it "falls back to RSpec.reset where clear_examples is unavailable" do
    allow(RSpec).to receive(:respond_to?).and_call_original
    allow(RSpec).to receive(:respond_to?).with(:clear_examples).and_return(false)

    runner.call("spec/foo_spec.rb")

    expect(RSpec).to have_received(:reset)
    expect(RSpec).not_to have_received(:clear_examples)
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

  # Runs the runner for real, in a process of its own: a nested in-process
  # RSpec run would share this suite's world and configuration.
  describe "against a real project" do
    let(:lib_dir) { File.expand_path("../../../../lib", __dir__) }

    def write(dir, path, body)
      full = File.join(dir, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, body)
    end

    def run_baseline(dir, preload: true)
      script = <<~RUBY
        require "json"
        require "rspec/core"
        require "evilution"
        require "evilution/baseline"
        require "evilution/integration/rspec/baseline_runner"
        $LOAD_PATH.unshift(File.expand_path("spec"))
        require "spec_helper" if #{preload}
        report = Evilution::Integration::RSpec::BaselineRunner.new.call("spec/x_spec.rb")
        $stdout.puts(JSON.generate(report))
      RUBY
      out, err, = Open3.capture3(RbConfig.ruby, "-I", lib_dir, "-e", script, chdir: dir)
      JSON.parse(out.lines.last || raise("no report: #{err}"), symbolize_names: true)
    end

    around do |example|
      Dir.mktmpdir("baseline_runner_real") do |dir|
        @dir = dir
        write(dir, "spec/spec_helper.rb", <<~RUBY)
          module Greeting
            def greet = "hi"
          end
          RSpec.configure { |config| config.include Greeting }
        RUBY
        example.run
      end
    end

    it "passes a spec relying on configuration from a preloaded helper" do
      write(@dir, "spec/x_spec.rb", <<~RUBY)
        require "spec_helper"
        RSpec.describe "x" do
          it("uses the configured helper") { expect(greet).to eq("hi") }
        end
      RUBY

      expect(run_baseline(@dir)).to eq(passed: true, failure_count: 0, failures: [], error: nil)
    end

    it "reports each failing example with its id, description and first error line" do
      write(@dir, "spec/x_spec.rb", <<~RUBY)
        require "spec_helper"
        RSpec.describe "x" do
          it("passes") { expect(1).to eq(1) }
          it("compares") { expect(1).to eq(2) }
          it("raises") { raise ArgumentError, "bad input" }
        end
      RUBY

      report = run_baseline(@dir)

      expect(report[:passed]).to be(false)
      expect(report[:failure_count]).to eq(2)
      expect(report[:error]).to be_nil
      expect(report[:failures]).to eq(
        [
          { id: "./spec/x_spec.rb[1:2]", description: "x compares",
            message: "RSpec::Expectations::ExpectationNotMetError: expected: 2 got: 1" },
          { id: "./spec/x_spec.rb[1:3]", description: "x raises", message: "ArgumentError: bad input" }
        ]
      )
    end

    it "reports what RSpec printed when the file fails outside any example" do
      write(@dir, "spec/x_spec.rb", <<~RUBY)
        require "spec_helper"
        UndefinedThing.call
      RUBY

      report = run_baseline(@dir)

      expect(report[:passed]).to be(false)
      expect(report[:failures]).to eq([])
      expect(report[:error]).to include("An error occurred while loading ./spec/x_spec.rb")
      expect(report[:error]).to include("uninitialized constant UndefinedThing")
    end
  end
end
