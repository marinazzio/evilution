# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::LoopBodyToRaise do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/loop_body_to_raise.rb", __dir__) }
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subject)
  end

  # Isolate the mutated method so an expectation reads as the resulting source
  # rather than a byte offset.
  def mutated_bodies(muts, method_name)
    muts.map { |m| m.mutated_source[/  def #{method_name}\b.*?\n  end\n/m] }
  end

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["loop_body_to_raise", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "replaces a while body with raise" do
      muts = mutations_for("count_up")

      expect(mutated_bodies(muts, "count_up")).to eq(
        ["  def count_up(limit)\n    i = 0\n    while i < limit\n      raise\n    end\n    i\n  end\n"]
      )
    end

    it "replaces an until body with raise" do
      muts = mutations_for("count_down")

      expect(mutated_bodies(muts, "count_down")).to eq(
        ["  def count_down(n)\n    until n.zero?\n      raise\n    end\n    n\n  end\n"]
      )
    end

    it "replaces a multi-statement body with a single raise" do
      muts = mutations_for("multi_statement")

      expect(mutated_bodies(muts, "multi_statement")).to eq(
        ["  def multi_statement(items)\n    while items.any?\n      raise\n    end\n  end\n"]
      )
    end

    it "replaces the body of a modifier while" do
      muts = mutations_for("modifier")

      expect(mutated_bodies(muts, "modifier")).to eq(
        ["  def modifier(queue)\n    raise while queue.any?\n  end\n"]
      )
    end

    # The begin/end wrapper has to stay: `raise while c` would check the
    # predicate before running the body, which is the opposite of what a
    # post-form loop guarantees.
    it "replaces the body of a post-form loop without unwrapping it" do
      muts = mutations_for("post_form")

      expect(mutated_bodies(muts, "post_form")).to eq(
        ["  def post_form(queue)\n    begin\n      raise\n    end while queue.any?\n  end\n"]
      )
    end

    it "replaces the body of a post-form until without unwrapping it" do
      muts = mutations_for("post_form_until")

      expect(mutated_bodies(muts, "post_form_until")).to eq(
        ["  def post_form_until(queue)\n    begin\n      raise\n    end until queue.empty?\n  end\n"]
      )
    end

    it "emits nothing for an empty loop body" do
      muts = mutations_for("empty_body")

      expect(muts).to be_empty
    end

    it "emits nothing when the body is already a bare raise" do
      muts = mutations_for("already_raises")

      expect(muts).to be_empty
    end

    # A literal body has no #name at all, so the CallNode check is what keeps
    # the raise comparison from reaching for one.
    it "mutates a body that is a bare literal" do
      muts = mutations_for("literal_body")

      expect(mutated_bodies(muts, "literal_body")).to eq(
        ["  def literal_body(flag)\n    while flag\n      raise\n    end\n  end\n"]
      )
    end

    # A receiverless, argumentless call is the shape a bare `raise` has; only
    # the method name separates them.
    it "mutates a body that is a single bare call other than raise" do
      muts = mutations_for("bare_call_body")

      expect(mutated_bodies(muts, "bare_call_body")).to eq(
        ["  def bare_call_body(flag)\n    while flag\n      raise\n    end\n  end\n"]
      )
    end

    it "mutates a body whose leading statement is a bare raise" do
      muts = mutations_for("raise_comes_first")

      expect(mutated_bodies(muts, "raise_comes_first")).to eq(
        ["  def raise_comes_first(queue)\n    while queue.any?\n      raise\n    end\n  end\n"]
      )
    end

    it "still mutates a body whose raise carries a message" do
      muts = mutations_for("raises_with_message")

      expect(mutated_bodies(muts, "raises_with_message")).to eq(
        ["  def raises_with_message(flag)\n    while flag\n      raise\n    end\n  end\n"]
      )
    end

    it "still mutates a body whose raise has an explicit receiver" do
      muts = mutations_for("raises_via_receiver")

      expect(mutated_bodies(muts, "raises_via_receiver")).to eq(
        ["  def raises_via_receiver(flag)\n    while flag\n      raise\n    end\n  end\n"]
      )
    end

    it "still mutates a body where the bare raise is one statement among several" do
      muts = mutations_for("raise_is_not_alone")

      expect(mutated_bodies(muts, "raise_is_not_alone")).to eq(
        ["  def raise_is_not_alone(queue)\n    while queue.any?\n      raise\n    end\n  end\n"]
      )
    end

    it "keeps the rescue clause of a post-form loop body" do
      muts = mutations_for("post_form_with_rescue")

      expect(mutated_bodies(muts, "post_form_with_rescue")).to eq(
        ["  def post_form_with_rescue(queue)\n    begin\n      raise\n    rescue StandardError\n      " \
         "nil\n    end while queue.any?\n  end\n"]
      )
    end

    it "mutates each loop of a nested until pair" do
      muts = mutations_for("nested_until")

      expect(muts.length).to eq(2)
      expect(mutated_bodies(muts, "nested_until").last).to include(
        "until cols.empty?\n        raise\n      end"
      )
    end

    it "mutates each loop of a nested pair" do
      muts = mutations_for("nested")

      expect(muts.length).to eq(2)
      expect(mutated_bodies(muts, "nested").last).to include("while cols.any?\n        raise\n      end")
    end

    it "reports the mutation on the line of the loop" do
      muts = mutations_for("count_up")

      expect(muts.map(&:line)).to eq([4])
    end

    it "names the operator" do
      muts = mutations_for("count_up")

      expect(muts.map(&:operator_name)).to eq(["loop_body_to_raise"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("count_up") + mutations_for("modifier") + mutations_for("post_form")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "emits nothing for a method without loops" do
      muts = mutations_from_source("def plain(a, b)\n  a + b\nend\n")

      expect(muts).to be_empty
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["while"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#count_up") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
