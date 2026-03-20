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

  it "handles released node gracefully" do
    subj = subject_for("method_with_dead_code")
    subj.release_node!
    mutation = double("Mutation", operator_name: "statement_deletion", subject: subj, line: 20)

    expect(heuristic.match?(mutation)).to be false
  end
end
