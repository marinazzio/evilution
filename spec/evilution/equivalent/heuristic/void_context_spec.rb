# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::VoidContext do
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

  def find_line_in_method(subj, pattern)
    start = subj.line_number
    source.lines.each_with_index do |line, idx|
      line_num = idx + 1
      return line_num if line_num > start && line.include?(pattern)
    end
    raise "Pattern #{pattern.inspect} not found after line #{start}"
  end

  describe "each -> map in void context" do
    it "matches when .each is not the last statement" do
      subj = subject_for("each_in_void_context")
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].each { |x| puts x }\n+ [1, 2, 3].map { |x| puts x }")

      expect(heuristic.match?(mutation)).to be true
    end

    it "matches in a method with multiple statements" do
      subj = subject_for("each_void_multi_statement")
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].each { |x| puts x }\n+ [1, 2, 3].map { |x| puts x }")

      expect(heuristic.match?(mutation)).to be true
    end
  end

  describe "each -> map NOT in void context" do
    it "does not match when .each is the last expression (return value)" do
      subj = subject_for("each_as_return_value")
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].each { |x| puts x }\n+ [1, 2, 3].map { |x| puts x }")

      expect(heuristic.match?(mutation)).to be false
    end

    it "does not match when .each return value is assigned" do
      subj = subject_for("each_assigned")
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "- result = [1, 2, 3].each { |x| puts x }\n+ result = [1, 2, 3].map { |x| puts x }")

      expect(heuristic.match?(mutation)).to be false
    end
  end

  describe "map -> each in void context" do
    it "matches when .map is not the last statement" do
      subj = subject_for("map_in_void_context")
      line = find_line_in_method(subj, ".map")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].map { |x| x * 2 }\n+ [1, 2, 3].each { |x| x * 2 }")

      expect(heuristic.match?(mutation)).to be true
    end

    it "does not match when .map is the last expression" do
      subj = subject_for("map_as_return_value")
      line = find_line_in_method(subj, ".map")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].map { |x| x * 2 }\n+ [1, 2, 3].each { |x| x * 2 }")

      expect(heuristic.match?(mutation)).to be false
    end
  end

  describe "each -> reverse_each in void context" do
    it "matches when .each is not the last statement" do
      subj = subject_for("each_in_void_context")
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "send_mutation",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].each { |x| puts x }\n+ [1, 2, 3].reverse_each { |x| puts x }")

      expect(heuristic.match?(mutation)).to be true
    end

    it "does not match when .each is the last expression" do
      subj = subject_for("each_as_return_value")
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "send_mutation",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].each { |x| puts x }\n+ [1, 2, 3].reverse_each { |x| puts x }")

      expect(heuristic.match?(mutation)).to be false
    end
  end

  describe "edge cases" do
    it "does not match non-matching operators" do
      subj = subject_for("each_in_void_context")
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "comparison_replacement",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].each { |x| puts x }\n+ [1, 2, 3].map { |x| puts x }")

      expect(heuristic.match?(mutation)).to be false
    end

    it "does not match non-void-equivalent method swaps" do
      subj = subject_for("each_in_void_context")
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "send_mutation",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].select { |x| x > 1 }\n+ [1, 2, 3].reject { |x| x > 1 }")

      expect(heuristic.match?(mutation)).to be false
    end

    it "handles released node gracefully" do
      subj = subject_for("each_in_void_context")
      subj.release_node!
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].each { |x| puts x }\n+ [1, 2, 3].map { |x| puts x }")

      expect(heuristic.match?(mutation)).to be false
    end

    it "does not match when the diff has no removed line" do
      # extract_method_pair finds no "- " line, so `removed` is nil. The
      # guards must reject before calling to_sym / match on nil.
      subj = subject_for("each_in_void_context")
      line = find_line_in_method(subj, ".each")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "+ [1, 2, 3].map { |x| puts x }")

      expect(heuristic.match?(mutation)).to be false
    end

    it "does not match when the method body is not a plain statements node" do
      # A rescue clause gives the method a BeginNode body. void_context?
      # must reject it via the StatementsNode type guard.
      rescue_source = "def guarded\n  [1, 2, 3].each { |x| x }\nrescue StandardError\n  nil\nend\n"
      parsed = Prism.parse(rescue_source).value
      finder = Evilution::AST::SubjectFinder.new(rescue_source, "rescue.rb")
      finder.visit(parsed)
      subj = finder.subjects.first
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: 2,
                        diff: "- [1, 2, 3].each { |x| x }\n+ [1, 2, 3].map { |x| x }")

      expect(heuristic.match?(mutation)).to be false
    end

    it "does not match when no call starts on the mutation line" do
      # The mutation line points at an interior line of a multi-line .each
      # call; no statement begins there. find_call_at_line must return nil
      # so the call_node guard rejects the mutation.
      subj = subject_for("each_multiline_void")
      line = find_line_in_method(subj, "puts x")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].each { |x| puts x }\n+ [1, 2, 3].map { |x| puts x }")

      expect(heuristic.match?(mutation)).to be false
    end

    it "does not match when the call is the last statement (multi-statement method)" do
      # The mutation line is the final statement of a multi-statement
      # method, so the call's return value is the method's return value.
      # void_context? must use the actual statement index, not the first
      # call in the method.
      subj = subject_for("each_void_multi_statement")
      line = find_line_in_method(subj, "cleanup_something")
      mutation = double("Mutation",
                        operator_name: "collection_replacement",
                        subject: subj,
                        line: line,
                        diff: "- [1, 2, 3].each { |x| puts x }\n+ [1, 2, 3].map { |x| puts x }")

      expect(heuristic.match?(mutation)).to be false
    end
  end
end
