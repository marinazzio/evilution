# frozen_string_literal: true

require "open3"
require "evilution/config"
require "evilution/baseline"
require "evilution/mutation"
require "evilution/runner/mutation_executor/timeout_policy"

RSpec.describe Evilution::Runner::MutationExecutor::TimeoutPolicy do
  let(:mutation) { instance_double(Evilution::Mutation, file_path: "lib/foo.rb") }

  def config(**options)
    Evilution::Config.new(quiet: true, skip_config_file: true, spec_files: ["spec/foo_spec.rb"], **options)
  end

  def baseline(durations: { "spec/foo_spec.rb" => 0.5 })
    Evilution::Baseline::Result.new(failed_spec_files: Set.new, duration: 1.0, spec_file_durations: durations)
  end

  describe ".build" do
    it "derives each limit from the baseline when no timeout was given" do
      policy = described_class.build(config, baseline(durations: { "spec/foo_spec.rb" => 2.0 }))

      expect(policy.call(mutation)).to eq(20.0)
    end

    it "keeps an explicitly given timeout for every mutation" do
      policy = described_class.build(config(timeout: 45), baseline(durations: { "spec/foo_spec.rb" => 2.0 }))

      expect(policy.call(mutation)).to eq(45)
    end

    it "keeps the default timeout when no baseline ran" do
      expect(described_class.build(config, nil).call(mutation)).to eq(30)
    end

    # The heuristic adds spec files per mutation that the baseline never ran,
    # so it has no time to scale for them.
    it "keeps the default timeout when related specs are added per mutation" do
      policy = described_class.build(config(related_specs_heuristic: true), baseline)

      expect(policy.call(mutation)).to eq(30)
    end

    it "passes the configured factor, floor and ceiling on" do
      cfg = config(timeout_factor: 3, timeout_floor: 1, timeout_ceiling: 5)

      expect(described_class.build(cfg, baseline(durations: { "spec/foo_spec.rb" => 1.0 })).call(mutation)).to eq(3.0)
      expect(described_class.build(cfg, baseline(durations: { "spec/foo_spec.rb" => 0.1 })).call(mutation)).to eq(1)
      expect(described_class.build(cfg, baseline(durations: { "spec/foo_spec.rb" => 9.0 })).call(mutation)).to eq(5)
    end

    it "resolves spec files through the run's spec selector" do
      cfg = Evilution::Config.new(quiet: true, skip_config_file: true,
                                  spec_mappings: { "lib/foo.rb" => ["spec/support/fixtures/simple_class.rb"] })
      durations = { "spec/support/fixtures/simple_class.rb" => 1.5 }

      expect(described_class.build(cfg, baseline(durations: durations)).call(mutation)).to eq(15.0)
    end
  end

  # A project that turns warnings into exceptions (dry-monads does) loads
  # this lazily, after its spec helper ran, so a warning here fails the run.
  it "loads lazily without a warning" do
    script = <<~RUBY
      require "evilution"
      require "evilution/runner"
      $VERBOSE = true
      Evilution::Runner::MutationExecutor::TimeoutPolicy::Adaptive
    RUBY
    _out, err, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../../../../lib", __dir__), "-e", script)

    expect(status).to be_success
    expect(err).not_to include("warning")
  end
end
