# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::GuardedIndexFetch do
  subject(:heuristic) { described_class.new }

  let(:fixture_path) { File.expand_path("../../../support/fixtures/guarded_index_fetch.rb", __dir__) }
  let(:source) { File.read(fixture_path) }

  def subject_for(method_name)
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(Prism.parse(source).value)
    finder.subjects.find { |s| s.name.end_with?("##{method_name}") }
  end

  def mutations_for(method_name)
    Evilution::Mutator::Operator::IndexToFetch.new.call(subject_for(method_name))
  end

  # One verdict per `recv[key]` read of the method, in source order; a chained
  # read (`a[:x][:y]`) lists the outer one first.
  def verdicts(method_name)
    mutations_for(method_name)
      .each_with_index
      .sort_by { |mutation, index| [mutation.line, mutation.column, index] }
      .map { |mutation, _index| heuristic.match?(mutation) }
  end

  describe "guard shapes" do
    it "leaves an unguarded read alone" do
      expect(verdicts("unguarded")).to eq([false])
    end

    it "matches the read under an if on the same read, never the condition itself" do
      expect(verdicts("if_guard")).to eq([false, true])
    end

    it "matches the read guarded by a modifier if" do
      expect(verdicts("modifier_if")).to eq([true, false])
    end

    it "does not match the read guarded by a modifier unless" do
      expect(verdicts("modifier_unless")).to eq([false, false])
    end

    it "matches the true branch of a ternary" do
      expect(verdicts("ternary")).to eq([false, true])
    end

    it "does not match the false branch of a ternary" do
      expect(verdicts("ternary_else")).to eq([false, false])
    end

    it "does not match the else branch of an if" do
      expect(verdicts("else_branch")).to eq([false, false])
    end

    it "matches only the else branch of an unless" do
      expect(verdicts("unless_else")).to eq([false, false, true])
    end

    it "matches only the branch its own elsif guards" do
      expect(verdicts("elsif_guard")).to eq([false, false, true, false])
    end

    it "matches the right side of &&" do
      expect(verdicts("and_guard")).to eq([false, true])
    end

    it "matches the right side of and" do
      expect(verdicts("and_keyword")).to eq([false, true])
    end

    it "matches the right side of a longer && chain" do
      expect(verdicts("and_chain")).to eq([false, true])
    end

    it "does not match the right side of ||" do
      expect(verdicts("or_guard")).to eq([false, false])
    end

    it "matches when the read is one conjunct of the condition" do
      expect(verdicts("conjunct_guard")).to eq([false, true])
    end

    it "sees through parentheses in the condition" do
      expect(verdicts("parenthesized_guard")).to eq([false, true])
    end

    it "matches when the read is the first conjunct of the condition" do
      expect(verdicts("left_conjunct_guard")).to eq([false, true])
    end

    it "does not match when no conjunct is the read" do
      expect(verdicts("unrelated_conjuncts")).to eq([false])
    end

    it "does not look past the first statement of a parenthesized sequence" do
      expect(verdicts("parenthesized_sequence_guard")).to eq([false, false])
    end

    it "does not take a parenthesized sequence for its first statement" do
      expect(verdicts("parenthesized_sequence_ending_elsewhere")).to eq([false, false])
    end

    it "does not match a parenthesized condition that is not the read" do
      expect(verdicts("parenthesized_unrelated_guard")).to eq([false])
    end

    it "does not match when the read is one disjunct of the condition" do
      expect(verdicts("disjunct_guard")).to eq([false, false])
    end

    it "does not match under a negated condition" do
      expect(verdicts("negated_guard")).to eq([false, false])
    end

    it "does not match under a loop condition" do
      expect(verdicts("while_guard")).to eq([false, false])
    end

    it "matches a read nested deeper inside the guarded branch" do
      expect(verdicts("nested_ifs")).to eq([false, true])
    end
  end

  describe "the same read" do
    it "requires the same key" do
      expect(verdicts("different_key")).to eq([false, false])
    end

    it "requires the same receiver" do
      expect(verdicts("different_receiver")).to eq([false, false])
    end

    it "tells a symbol key from a string key" do
      expect(verdicts("symbol_and_string_key")).to eq([false, false])
    end

    it "matches a string key" do
      expect(verdicts("string_key")).to eq([false, true])
    end

    it "matches an integer key" do
      expect(verdicts("integer_key")).to eq([false, true])
    end

    it "does not match a key that is not a literal" do
      expect(verdicts("dynamic_key")).to eq([false, false])
    end

    it "matches the inner read of a chain, not the outer one" do
      expect(verdicts("nested_index")).to eq([false, false, true])
    end
  end

  describe "conditions other than the read itself" do
    %w[key_predicate has_key_predicate include_predicate member_predicate].each do |method_name|
      it "matches under #{method_name.sub("_predicate", "?")} on the same receiver and key" do
        expect(verdicts(method_name)).to eq([true])
      end
    end

    it "does not match a key predicate on another key" do
      expect(verdicts("key_predicate_other_key")).to eq([false])
    end

    it "does not match a key predicate on another receiver" do
      expect(verdicts("key_predicate_other_receiver")).to eq([false])
    end

    it "does not match an unrelated call given the same key" do
      expect(verdicts("unrelated_call_with_key")).to eq([false])
    end

    it "does not match present? on another read" do
      expect(verdicts("present_on_other_read")).to eq([false, false])
    end

    it "does not match an unrelated predicate on the receiver" do
      expect(verdicts("unrelated_predicate")).to eq([false])
    end

    it "matches under present? on the same read, never the read inside the condition" do
      expect(verdicts("present_guard")).to eq([false, true])
    end

    it "does not match under blank?" do
      expect(verdicts("blank_guard")).to eq([false, false])
    end

    it "matches under a single-key dig" do
      expect(verdicts("dig_guard")).to eq([true])
    end

    it "does not match under a deeper dig" do
      expect(verdicts("deep_dig_guard")).to eq([false])
    end
  end

  describe "receivers" do
    it "matches an instance variable" do
      expect(verdicts("ivar_receiver")).to eq([false, true])
    end

    it "matches a constant" do
      expect(verdicts("constant_receiver")).to eq([false, true])
    end

    it "matches a method call without arguments" do
      expect(verdicts("method_receiver")).to eq([false, true])
    end

    it "matches a chain of calls without arguments" do
      expect(verdicts("chained_receiver")).to eq([false, true])
    end

    it "matches a call on self" do
      expect(verdicts("self_receiver")).to eq([false, true])
    end

    it "does not match a call with arguments" do
      expect(verdicts("receiver_with_arguments")).to eq([false, false])
    end

    it "does not match a call with a block" do
      expect(verdicts("receiver_with_block")).to eq([false, false])
    end
  end

  describe "a receiver that changes inside the guarded branch" do
    %w[reassigned or_assigned multi_assigned ivar_reassigned chain_root_reassigned].each do |method_name|
      it "does not match when the receiver is #{method_name.tr("_", " ")}" do
        expect(verdicts(method_name)).to eq([false, false])
      end
    end

    it "matches when another variable is assigned" do
      expect(verdicts("other_variable_assigned")).to eq([false, true])
    end

    it "does not match when a key is deleted from the receiver" do
      expect(verdicts("deleted")).to eq([false, false])
    end

    it "does not match when the receiver is assigned through []=" do
      expect(verdicts("index_assigned")).to eq([false, false])
    end

    it "does not match when a bang method is called on the receiver" do
      expect(verdicts("bang_mutated")).to eq([false, false])
    end

    it "matches when another receiver is mutated" do
      expect(verdicts("other_receiver_mutated")).to eq([false, true])
    end

    it "matches when the receiver is only read" do
      expect(verdicts("read_only_call")).to eq([false, true])
    end
  end

  describe "scopes" do
    it "matches a read inside a block in the guarded branch" do
      expect(verdicts("inside_block")).to eq([false, true])
    end

    it "does not match a block parameter shadowing the receiver" do
      expect(verdicts("shadowed_by_block_parameter")).to eq([false, false])
    end

    it "does not match a read inside a lambda" do
      expect(verdicts("inside_lambda")).to eq([false, false])
    end

    it "does not match a read inside a nested method definition" do
      expect(verdicts("inside_nested_def")).to eq([false, false])
    end
  end

  describe "early exits" do
    describe "guard shapes" do
      %w[return_unless return_value_unless raise_unless fail_unless].each do |method_name|
        it "matches the read after `#{method_name.tr("_", " ")}`, never the guard itself" do
          expect(verdicts(method_name)).to eq([false, true])
        end
      end

      it "matches after an unless block that ends in an exit" do
        expect(verdicts("block_unless")).to eq([false, true])
      end

      it "does not match after an unless that does not exit" do
        expect(verdicts("unless_without_exit")).to eq([false, false])
      end

      it "does not match when the exit is not the block's last statement" do
        expect(verdicts("unless_exit_not_last")).to eq([false, false])
      end

      # The else branch is guarded by the unless itself. What follows the whole
      # statement is left alone: an else can do anything to the receiver on
      # its way through.
      it "matches the else branch of an unless-exit, but not what follows it" do
        expect(verdicts("unless_with_else")).to eq([false, true, false])
      end

      it "matches after `cond or return`" do
        expect(verdicts("or_return")).to eq([false, true])
      end

      it "matches after `cond || raise`" do
        expect(verdicts("double_pipe_raise")).to eq([false, true])
      end

      it "does not match after `cond or` something that does not leave" do
        expect(verdicts("or_without_exit")).to eq([false, false])
      end

      it "does not match after `other or return`" do
        expect(verdicts("or_exit_on_other")).to eq([false])
      end

      it "does not take a raise sent to a receiver for an exit" do
        expect(verdicts("raise_on_receiver_unless")).to eq([false, false])
      end

      it "does not take any bare call for an exit" do
        expect(verdicts("bare_call_unless")).to eq([false, false])
      end

      it "does not match after an empty unless" do
        expect(verdicts("empty_unless")).to eq([false, false])
      end

      it "does not match after `cond and return`" do
        expect(verdicts("and_return")).to eq([false, false])
      end

      it "matches the rest of an iteration after next" do
        expect(verdicts("next_unless")).to eq([false, true])
      end

      it "matches the rest of an iteration after break" do
        expect(verdicts("break_unless")).to eq([false, true])
      end
    end

    describe "conditions that exit when the key is missing" do
      %w[return_if_nil return_if_blank return_if_negated return_if_not].each do |method_name|
        it "matches after `#{method_name.tr("_", " ")}`" do
          expect(verdicts(method_name)).to eq([false, true])
        end
      end

      it "matches after an exit on a missing key predicate" do
        expect(verdicts("return_if_key_missing")).to eq([true])
        expect(verdicts("return_if_negated_key")).to eq([true])
      end

      it "matches when the missing-key test is either side of an or" do
        expect(verdicts("return_if_nil_or_other")).to eq([false, true])
        expect(verdicts("return_if_nil_first_or_other")).to eq([false, true])
      end

      it "sees through parentheses, but not into a sequence" do
        expect(verdicts("return_if_parenthesized_nil")).to eq([false, true])
        expect(verdicts("return_if_parenthesized_sequence")).to eq([false, false])
      end

      it "does not match an or, or parentheses, around tests of something else" do
        expect(verdicts("return_if_unrelated_or")).to eq([false])
        expect(verdicts("return_if_parenthesized_other")).to eq([false])
      end

      it "does not match a missing-key test on another read" do
        expect(verdicts("return_if_other_read_nil")).to eq([false, false])
      end

      it "does not match the negation of something that is not the read" do
        expect(verdicts("return_if_not_other")).to eq([false])
      end

      it "does not match when the missing-key test is one side of an and" do
        expect(verdicts("return_if_nil_and_other")).to eq([false, false])
      end

      it "does not match after an exit taken when the key is there" do
        expect(verdicts("return_if_present")).to eq([false, false])
      end

      it "does not match after an exit on a test that says nothing about presence" do
        expect(verdicts("return_if_empty")).to eq([false, false])
      end

      it "matches when the read is one conjunct of an unless condition" do
        expect(verdicts("return_unless_conjunct")).to eq([false, true])
      end

      it "does not match when the read is one disjunct of an unless condition" do
        expect(verdicts("return_unless_disjunct")).to eq([false, false])
      end

      it "matches after an if block that exits" do
        expect(verdicts("if_block_exit")).to eq([false, true])
      end

      it "does not match after an if-exit that has an else" do
        expect(verdicts("if_exit_with_else")).to eq([false, false])
      end

      it "requires the same key" do
        expect(verdicts("exit_guard_other_key")).to eq([false, false])
      end
    end

    describe "where the read is" do
      it "does not match a read before the guard" do
        expect(verdicts("read_before_guard")).to eq([false, false])
      end

      it "matches a read nested in a later statement" do
        expect(verdicts("read_in_later_branch")).to eq([false, true])
        expect(verdicts("read_in_later_block")).to eq([false, true])
      end

      it "matches through an inner statement list when the guard is in an outer one" do
        expect(verdicts("guard_in_outer_list")).to eq([false, true])
      end

      it "does not match when the guard only ends an inner branch" do
        expect(verdicts("guard_in_inner_list_only")).to eq([false, false])
      end

      it "does not match when the guard only ends an earlier block's iteration" do
        expect(verdicts("guard_in_earlier_block")).to eq([false, false])
      end

      it "does not match a read inside a lambda" do
        expect(verdicts("read_in_lambda_after_guard")).to eq([false, false])
      end

      it "does not match a read in a rescue clause" do
        expect(verdicts("read_in_rescue_after_guard")).to eq([false, false])
      end

      it "does not match a block parameter shadowing the receiver" do
        expect(verdicts("guard_then_shadowing_block")).to eq([false, false])
      end
    end

    describe "a receiver that changes after the guard" do
      it "does not match when the receiver is reassigned in between" do
        expect(verdicts("reassigned_after_guard")).to eq([false, false])
      end

      it "does not match when the receiver is mutated in between" do
        expect(verdicts("mutated_after_guard")).to eq([false, false])
      end

      it "does not match when the statement holding the read mutates the receiver" do
        expect(verdicts("mutated_in_read_statement")).to eq([false, false])
      end

      it "matches when only the guard's own exit branch changes the receiver" do
        expect(verdicts("guard_that_cleans_up_before_leaving")).to eq([false, true])
      end

      it "goes by the last guard before the read" do
        expect(verdicts("guarded_again_after_a_change")).to eq([false, false, true])
      end

      it "matches when the receiver is mutated only after the read's statement" do
        expect(verdicts("mutated_after_read")).to eq([false, true])
      end
    end
  end

  describe "mutations it has no business with" do
    let(:mutation) { mutations_for("if_guard").last }

    it "ignores other operators" do
      other = instance_double(Evilution::Mutation, operator_name: "send_mutation")

      expect(heuristic.match?(other)).to be(false)
    end

    it "does not match when the subject has no node" do
      bare = instance_double(Evilution::Mutation, operator_name: "index_to_fetch", mutated_source: source,
                                                  subject: double("Subject", node: nil))

      expect(heuristic.match?(bare)).to be(false)
    end

    it "does not match once the sources are stripped" do
      mutation.strip_sources!

      expect(heuristic.match?(mutation)).to be(false)
    end
  end

  it "is one of the detector's default heuristics" do
    equivalent, remaining = Evilution::Equivalent::Detector.new.call(mutations_for("if_guard"))

    expect(equivalent.map(&:line)).to eq([13])
    expect(remaining.map(&:line)).to eq([12])
  end
end
