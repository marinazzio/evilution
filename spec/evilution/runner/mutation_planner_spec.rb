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

      # Mutations OUTSIDE the disable-comment ranges must remain enabled: the
      # disabled-range check must actually test line membership, not blindly
      # treat every range as a match.
      expect(plan.enabled).not_to be_empty
      expect(plan.enabled.map(&:line)).to all(satisfy { |l| !disabled_method_line_range.cover?(l) })
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

      # Mutations OUTSIDE the sig block range must remain enabled: the sig-block
      # check must test line membership, not blindly treat every range as a match.
      expect(plan.enabled).not_to be_empty
      expect(plan.enabled.map(&:line).reject { |l| l == 3 }).not_to be_empty
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

    # EV-74e3: two operators can independently produce the same byte change
    # (e.g. statement_deletion + last_expression_removal for a multi-stmt
    # method whose tail is a literal). Running both is wasted compute and
    # inflates the denominator. Dedupe by (file_path, mutated_source) before
    # the filtering pipeline.
    it "deduplicates mutations with identical mutated_source within the same file" do
      registry = Evilution::Mutator::Registry.new
      registry.register(Evilution::Mutator::Operator::LastExpressionRemoval)
      registry.register(Evilution::Mutator::Operator::StatementDeletion)

      subjects = subjects_for("spec/support/fixtures/last_expression_removal.rb")
      plan = described_class.new(config, registry: registry).call(subjects)

      # Within the predicate_true method (2-stmt body: log_something + true)
      # both operators produce a `true`-deletion mutation. After dedup there
      # is exactly one such mutation for predicate_true.
      predicate_true_subject = subjects.find { |s| s.name.include?("predicate_true") }
      predicate_true_line = predicate_true_subject.line_number
      predicate_true_true_deletions = plan.enabled.select do |m|
        m.diff =~ /^-\s*true\s*$/ && m.line >= predicate_true_line && m.line <= predicate_true_line + 3
      end

      expect(predicate_true_true_deletions.length).to eq(1),
                                                      "expected single true-deletion in predicate_true after dedup, " \
                                                      "got #{predicate_true_true_deletions.length}: " \
                                                      "#{predicate_true_true_deletions.map(&:operator_name)}"
    end

    it "preserves the first operator_name when deduping (stable order)" do
      registry = Evilution::Mutator::Registry.new
      # Register last_expression_removal FIRST so its mutation wins dedup.
      registry.register(Evilution::Mutator::Operator::LastExpressionRemoval)
      registry.register(Evilution::Mutator::Operator::StatementDeletion)

      subjects = subjects_for("spec/support/fixtures/last_expression_removal.rb")
      plan = described_class.new(config, registry: registry).call(subjects)

      predicate_true_subject = subjects.find { |s| s.name.include?("predicate_true") }
      predicate_true_line = predicate_true_subject.line_number
      predicate_true_mutations = plan.enabled.select do |m|
        m.diff =~ /^-\s*true\s*$/ && m.line >= predicate_true_line && m.line <= predicate_true_line + 3
      end
      expect(predicate_true_mutations.map(&:operator_name).uniq).to eq(["last_expression_removal"])
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
