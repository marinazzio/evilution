# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::MethodBodyNil do
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

  it "matches method_body_replacement on an empty method" do
    subj = subject_for("empty_method")
    mutation = double("Mutation", operator_name: "method_body_replacement", subject: subj)

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches method_body_replacement on a method that just returns nil" do
    subj = subject_for("nil_method")
    mutation = double("Mutation", operator_name: "method_body_replacement", subject: subj)

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match method_body_replacement on a method with real body" do
    subj = subject_for("normal_method")
    mutation = double("Mutation", operator_name: "method_body_replacement", subject: subj)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match other operators" do
    subj = subject_for("empty_method")
    mutation = double("Mutation", operator_name: "statement_deletion", subject: subj)

    expect(heuristic.match?(mutation)).to be false
  end

  it "handles released node gracefully" do
    subj = subject_for("empty_method")
    subj.release_node!
    mutation = double("Mutation", operator_name: "method_body_replacement", subject: subj)

    expect(heuristic.match?(mutation)).to be false
  end
end
