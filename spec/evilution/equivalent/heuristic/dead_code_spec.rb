# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::DeadCode do
  subject(:heuristic) { described_class.new }

  let(:fixture_path) { File.expand_path("../../../support/fixtures/equivalent_detection.rb", __dir__) }
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def subject_for(method_name)
    subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
  end

  it "matches statement deletion of code after unconditional return" do
    subj = subject_for("method_with_dead_code")
    # The "puts" and "x = 1" lines are after "return 42"
    dead_line = source.lines.index { |l| l.include?("puts \"unreachable\"") } + 1
    mutation = double("Mutation", operator_name: "statement_deletion", subject: subj, line: dead_line)

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches statement deletion of code after raise" do
    subj = subject_for("method_with_raise_dead_code")
    dead_line = source.lines.index { |l| l.include?("cleanup") } + 1
    mutation = double("Mutation", operator_name: "statement_deletion", subject: subj, line: dead_line)

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match statement deletion of reachable code" do
    subj = subject_for("normal_method")
    # "x + 2" is reachable
    line = source.lines.index { |l| l.include?("x + 2") } + 1
    mutation = double("Mutation", operator_name: "statement_deletion", subject: subj, line: line)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match code after conditional return" do
    subj = subject_for("method_with_conditional_return")
    # "x + 1" is after a conditional return, so it's reachable
    line = source.lines.index { |l| l.strip == "x + 1" } + 1
    mutation = double("Mutation", operator_name: "statement_deletion", subject: subj, line: line)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match non-statement-deletion operators" do
    subj = subject_for("method_with_dead_code")
    dead_line = source.lines.index { |l| l.include?("puts \"unreachable\"") } + 1
    mutation = double("Mutation", operator_name: "string_literal", subject: subj, line: dead_line)

    expect(heuristic.match?(mutation)).to be false
  end

  # EV-74e3 PR review #1236: last_expression_removal can win dedup over
  # statement_deletion for the same byte change. Dead-code classification
  # must hold regardless of which operator name surfaces, otherwise dedup
  # silently strips equivalent-classification for trailing literals after
  # return/raise.
  it "matches last_expression_removal as well (deduplicates with statement_deletion)" do
    subj = subject_for("method_with_dead_code")
    dead_line = source.lines.index { |l| l.include?("puts \"unreachable\"") } + 1
    mutation = double("Mutation", operator_name: "last_expression_removal", subject: subj, line: dead_line)

    expect(heuristic.match?(mutation)).to be true
  end

  it "handles released node gracefully" do
    subj = subject_for("method_with_dead_code")
    subj.release_node!
    mutation = double("Mutation", operator_name: "statement_deletion", subject: subj, line: 20)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not treat code after a plain (non-raise) call as unreachable" do
    # setup_something / cleanup_something are ordinary calls, not raise.
    # Only `raise` (and explicit return) terminate control flow; a plain
    # call must not mark following statements as dead code.
    subj = subject_for("each_void_multi_statement")
    line = source.lines.index { |l| l.include?("cleanup_something") } + 1
    mutation = double("Mutation", operator_name: "statement_deletion", subject: subj, line: line)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when the method body is not a plain statements node" do
    # A method with a rescue clause has a BeginNode body, not a
    # StatementsNode. The type guard must reject it instead of treating
    # the BeginNode as a statement list.
    rescue_source = "def guarded\n  do_work\nrescue StandardError => e\n  handle(e)\nend\n"
    parsed = Prism.parse(rescue_source).value
    finder = Evilution::AST::SubjectFinder.new(rescue_source, "rescue.rb")
    finder.visit(parsed)
    subj = finder.subjects.first
    mutation = double("Mutation", operator_name: "statement_deletion", subject: subj, line: 2)

    expect(heuristic.match?(mutation)).to be false
  end
end
