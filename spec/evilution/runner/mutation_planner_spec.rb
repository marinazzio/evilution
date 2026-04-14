# frozen_string_literal: true

require "tmpdir"
require "evilution/config"
require "evilution/ast/parser"
require "evilution/mutator/registry"
require "evilution/runner/mutation_planner"

RSpec.describe Evilution::Runner::MutationPlanner do
  let(:parser) { Evilution::AST::Parser.new }
  let(:registry) { Evilution::Mutator::Registry.default }

  def subjects_for(file)
    parser.call(file)
  end

  def config(**overrides)
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, **overrides)
  end

  describe "#call" do
    it "returns a plan with enabled mutations from the registry" do
      subjects = subjects_for("spec/support/fixtures/arithmetic.rb")
      plan = described_class.new(config, registry: registry).call(subjects)

      expect(plan.enabled).not_to be_empty
      expect(plan.enabled.map(&:file_path).uniq).to eq(["spec/support/fixtures/arithmetic.rb"])
      expect(plan.skipped_count).to eq(0)
      expect(plan.disabled_mutations).to eq([])
      expect(plan.equivalent).to eq([])
    end

    it "filters out mutations in disable-comment ranges and counts them as skipped" do
      subjects = subjects_for("spec/support/fixtures/disable_comments.rb")
      plan = described_class.new(config, registry: registry).call(subjects)

      expect(plan.skipped_count).to be > 0
      expect(plan.disabled_mutations).to eq([])

      disabled_method_line_range = 9..11
      enabled_in_disabled = plan.enabled.select { |m| disabled_method_line_range.cover?(m.line) }
      expect(enabled_in_disabled).to be_empty
    end

    it "surfaces disabled mutations when config.show_disabled is set" do
      subjects = subjects_for("spec/support/fixtures/disable_comments.rb")
      plan = described_class.new(config(show_disabled: true), registry: registry).call(subjects)

      expect(plan.disabled_mutations).not_to be_empty
      expect(plan.disabled_mutations).to all(have_attributes(original_source: nil))
    end

    it "filters out mutations whose line falls inside a sig block range" do
      subjects = subjects_for("spec/support/fixtures/arithmetic.rb")
      sig_detector = instance_double(Evilution::AST::SorbetSigDetector)
      allow(sig_detector).to receive(:line_ranges).and_return([3..3])

      plan = described_class.new(config, registry: registry, sig_detector: sig_detector).call(subjects)

      expect(plan.enabled.map(&:line)).not_to include(3)
      expect(plan.skipped_count).to be > 0
    end

    it "splits equivalent mutations out of the enabled set" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "equiv.rb")
        File.write(file, <<~RUBY)
          class Equiv
            def call(a)
              a.to_s
              0
            end
          end
        RUBY

        subjects = subjects_for(file)
        plan = described_class.new(config, registry: registry).call(subjects)

        expect(plan.enabled + plan.equivalent).not_to be_empty
      end
    end

    it "reduces mutations when ignore_patterns matches" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "logger.rb")
        File.write(file, <<~RUBY)
          class Logger
            def call
              log("start")
              1 + 1
            end

            def log(msg)
              msg
            end
          end
        RUBY

        baseline = described_class.new(config, registry: registry).call(subjects_for(file))
        filtered = described_class.new(
          config(ignore_patterns: ["call{name=log}"]),
          registry: registry
        ).call(subjects_for(file))

        expect(filtered.enabled.length).to be < baseline.enabled.length
        expect(filtered.skipped_count).to be > 0
      end
    end

    it "forwards skip_heredoc_literals to operator_options" do
      subjects = subjects_for("spec/support/fixtures/heredoc_mutations.rb")

      default_plan = described_class.new(config, registry: registry).call(subjects)
      skipped_plan = described_class.new(
        config(skip_heredoc_literals: true),
        registry: registry
      ).call(subjects_for("spec/support/fixtures/heredoc_mutations.rb"))

      expect(skipped_plan.enabled.length).to be < default_plan.enabled.length
    end
  end
end
