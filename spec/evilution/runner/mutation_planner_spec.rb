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

  # Anchored to this file, not the CWD: evilution mutating its own code runs
  # these examples in a worker whose CWD is a scratch sandbox.
  def fixture(name)
    File.expand_path("../../support/fixtures/#{name}", __dir__)
  end

  def config(**overrides)
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, **overrides)
  end

  describe "#call" do
    it "returns a plan with enabled mutations from the registry" do
      subjects = subjects_for(fixture("arithmetic.rb"))
      plan = described_class.new(config, registry: registry).call(subjects)

      expect(plan.enabled).not_to be_empty
      expect(plan.enabled.map(&:file_path).uniq).to eq([fixture("arithmetic.rb")])
      expect(plan.skipped_count).to eq(0)
      expect(plan.disabled_mutations).to eq([])
      expect(plan.equivalent).to eq([])
    end

    it "lists the lines mutations were generated for, per file" do
      file = fixture("arithmetic.rb")
      plan = described_class.new(config, registry: registry).call(subjects_for(file))

      expect(plan.mutated_lines.keys).to eq([file])
      expect(plan.mutated_lines[file]).to eq(plan.enabled.flat_map { |m| m.changed_lines.to_a }.uniq.sort)
    end

    it "counts a line whose mutations were disabled by a comment as mutated" do
      file = fixture("disable_comments.rb")
      plan = described_class.new(config, registry: registry).call(subjects_for(file))

      expect(plan.mutated_lines[file] & (9..11).to_a).not_to be_empty
    end

    it "filters out mutations in disable-comment ranges and counts them as skipped" do
      subjects = subjects_for(fixture("disable_comments.rb"))
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
      subjects = subjects_for(fixture("disable_comments.rb"))
      plan = described_class.new(config(show_disabled: true), registry: registry).call(subjects)

      expect(plan.disabled_mutations).not_to be_empty
      expect(plan.disabled_mutations).to all(have_attributes(original_source: nil))
    end

    it "filters out mutations whose line falls inside a sig block range" do
      subjects = subjects_for(fixture("arithmetic.rb"))
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

      subjects = subjects_for(fixture("last_expression_removal.rb"))
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

      subjects = subjects_for(fixture("last_expression_removal.rb"))
      plan = described_class.new(config, registry: registry).call(subjects)

      predicate_true_subject = subjects.find { |s| s.name.include?("predicate_true") }
      predicate_true_line = predicate_true_subject.line_number
      predicate_true_mutations = plan.enabled.select do |m|
        m.diff =~ /^-\s*true\s*$/ && m.line >= predicate_true_line && m.line <= predicate_true_line + 3
      end
      expect(predicate_true_mutations.map(&:operator_name).uniq).to eq(["last_expression_removal"])
    end

    context "with a line range" do
      let(:source) do
        <<~RUBY
          class Night
            KINDS = %i[day night].freeze

            def call(x)
              x + 1
            end

            def other(y)
              foo(y,
                  2)
            end
          end
        RUBY
      end

      def plan_for(dir, line_ranges = nil)
        file = File.join(dir, "night.rb")
        File.write(file, source)
        overrides = line_ranges ? { line_ranges: { file => line_ranges } } : {}
        [file, described_class.new(config(**overrides), registry: registry).call(subjects_for(file))]
      end

      def planned(plan)
        plan.enabled + plan.equivalent
      end

      it "leaves out the class-body mutations an in-range method is the anchor of" do
        Dir.mktmpdir do |dir|
          _, unranged = plan_for(dir)
          expect(planned(unranged).map(&:line)).to include(2)

          _, plan = plan_for(dir, 4..6)

          expect(planned(plan)).not_to be_empty
          expect(planned(plan).map(&:changed_lines)).to all(satisfy { |lines| lines.first <= 6 && lines.last >= 4 })
        end
      end

      it "keeps a mutation that starts before the range and changes a line inside it" do
        Dir.mktmpdir do |dir|
          _, unranged = plan_for(dir)
          expect(planned(unranged).map(&:changed_lines)).to include(9..9)

          _, plan = plan_for(dir, 10..10)

          expect(planned(plan).map(&:changed_lines)).to include(9..10)
          expect(planned(plan).map(&:changed_lines)).not_to include(9..9)
        end
      end

      it "has the operators build only the mutations that change a line of the range" do
        Dir.mktmpdir do |dir|
          allow(registry).to receive(:mutations_for).and_call_original

          file, = plan_for(dir, 4..6)

          expect(registry).to have_received(:mutations_for)
            .with(anything, filter: nil, operator_options: hash_including(line_ranges: { file => 4..6 })).at_least(:once)
        end
      end

      it "drops the mutations outside the range without counting them as skipped" do
        Dir.mktmpdir do |dir|
          _, plan = plan_for(dir, 4..6)

          expect(plan.skipped_count).to eq(0)
        end
      end

      it "lists only the lines of the mutations it kept as mutated" do
        Dir.mktmpdir do |dir|
          file, plan = plan_for(dir, 4..6)

          expect(plan.mutated_lines[file]).not_to include(2)
          expect(plan.mutated_lines[file]).to include(5)
        end
      end

      it "lists every line a kept mutation changes, not only the line it is reported at" do
        Dir.mktmpdir do |dir|
          file, plan = plan_for(dir, 10..10)
          changed = planned(plan).flat_map { |mutation| mutation.changed_lines.to_a }.uniq.sort

          expect(changed).to include(9, 10)
          expect(plan.mutated_lines[file]).to eq(changed)
        end
      end
    end

    it "forwards skip_heredoc_literals to operator_options" do
      subjects = subjects_for(fixture("heredoc_mutations.rb"))

      default_plan = described_class.new(config, registry: registry).call(subjects)
      skipped_plan = described_class.new(
        config(skip_heredoc_literals: true),
        registry: registry
      ).call(subjects_for(fixture("heredoc_mutations.rb")))

      expect(skipped_plan.enabled.length).to be < default_plan.enabled.length
    end
  end

  # Receiver simplifications (`x.to_i` -> `x`, `x.presence` -> `x`,
  # `x.to_s` -> `x`) must reach the plan in every context they are written
  # in, the value of a constant included. In argument and hash-value position
  # the identical bytes are also produced by argument_method_call_replacement,
  # which is registered first, so dedup reports them under that name rather
  # than method_call_removal.
  describe "receiver simplification" do
    let(:file) { fixture("receiver_simplification.rb") }
    let(:plan) { described_class.new(config, registry: registry).call(subjects_for(file)) }

    def line_of(mutation)
      mutation.mutated_source.lines[mutation.line - 1].strip
    end

    def simplified(line_text)
      plan.enabled.select { |m| line_of(m) == line_text }.map(&:operator_name)
    end

    {
      "LIMIT = ENV[\"SEAT_LIMIT\"]" => "method_call_removal",
      "SEATS = { first: \"1\" }.freeze" => "argument_method_call_replacement",
      "SEATS = { first: \"1\".to_i }" => "freeze_removal",
      "def label = value" => "method_call_removal",
      "params[:x]" => "method_call_removal",
      "\"seat \#{value}\"" => "method_call_removal",
      "value" => "method_call_removal",
      "def keyword_default(seat: raw_seat)" => "method_call_removal",
      "list.map { |str| str }" => "method_call_removal",
      "def call(seat_str:) = Seat.find_by(number: seat_str)" => "argument_method_call_replacement",
      "{ number: value }" => "argument_method_call_replacement"
    }.each do |line_text, operator_name|
      it "plans #{line_text.inspect} as an enabled #{operator_name} mutation" do
        expect(simplified(line_text)).to eq([operator_name])
      end
    end

    it "has method_call_removal generate the argument-position ones too, before dedup relabels them" do
      generated = subjects_for(file).flat_map { |s| registry.mutations_for(s) }
                                    .select { |m| m.operator_name == "method_call_removal" }.map { |m| line_of(m) }

      expect(generated).to include("def call(seat_str:) = Seat.find_by(number: seat_str)", "{ number: value }",
                                   "SEATS = { first: \"1\" }.freeze")
    end

    it "attributes a method written in a constant's value to the method, not the constant" do
      handled = plan.enabled.select { |m| line_of(m) == "def handle(raw) = raw" }

      expect(handled.map { |m| [m.operator_name, m.subject.kind] }).to eq([["method_call_removal", :method]])
    end
  end
end
