# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RescueElseConcatenation do
  def mutations_for(source, filter: nil)
    tmpfile = Tempfile.new(["rescue_else_concatenation", ".rb"])
    tmpfile.write(source)
    tmpfile.flush
    described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_sources(source, filter: nil)
    mutations_for(source, filter: filter).map(&:mutated_source)
  end

  describe "#call" do
    it "moves the else body into the protected body" do
      source = "def m(id)\n  begin\n    fetch(id)\n  rescue StandardError\n    default\n  else\n    notify\n  end\nend\n"

      expect(mutated_sources(source)).to eq(
        ["def m(id)\n  begin\n    fetch(id)\n    notify\n  rescue StandardError\n    default\n  end\nend\n"]
      )
    end

    it "moves a method-level else body" do
      source = "def m\n  a\nrescue\n  b\nelse\n  c\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  a\n  c\nrescue\n  b\nend\n"])
    end

    it "keeps an ensure clause after the rescue" do
      source = "def m\n  a\nrescue\n  b\nelse\n  c\nensure\n  d\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  a\n  c\nrescue\n  b\nensure\n  d\nend\n"])
    end

    it "moves every statement of a longer else body after every statement of the body" do
      source = "def m\n  a\n  b\nrescue\n  r\nelse\n  c\n  d\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  a\n  b\n  c\n  d\nrescue\n  r\nend\n"])
    end

    it "keeps every rescue clause" do
      source = "def m\n  a\nrescue\n  b\nrescue Y\n  c\nelse\n  d\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  a\n  d\nrescue\n  b\nrescue Y\n  c\nend\n"])
    end

    it "moves the else body of a block's rescue" do
      source = "def m(ids)\n  ids.each do |id|\n    fetch(id)\n  rescue StandardError\n    skip\n  else\n    count\n  end\nend\n"

      expect(mutated_sources(source)).to eq(
        ["def m(ids)\n  ids.each do |id|\n    fetch(id)\n    count\n  rescue StandardError\n    skip\n  end\nend\n"]
      )
    end

    it "keeps a one-line begin on one line" do
      source = "def m\n  begin; a; rescue; b; else; c; end\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  begin; a; c; rescue; b; end\nend\n"])
    end

    it "keeps an empty handler" do
      source = "def m\n  a\nrescue\nelse\n  c\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  a\n  c\nrescue\nend\n"])
    end

    # Moved under a rescue for one specific class, the else code changes
    # behaviour only if it raises that class, which it rarely does; such
    # mutants would mostly survive without telling anything.
    it "skips a rescue that catches only specific classes" do
      expect(mutated_sources("def m\n  a\nrescue NotFound, Timeout\n  b\nelse\n  c\nend\n")).to be_empty
    end

    it "counts a bare rescue and StandardError or Exception as broad" do
      %w[StandardError ::StandardError Exception ::Exception].each do |klass|
        expect(mutated_sources("def m\n  a\nrescue #{klass} => e\n  b(e)\nelse\n  c\nend\n").length).to eq(1)
      end
      expect(mutated_sources("def m\n  a\nrescue NotFound, StandardError\n  b\nelse\n  c\nend\n").length).to eq(1)
    end

    it "moves the else body when any one rescue clause is broad" do
      source = "def m\n  a\nrescue NotFound\n  b\nrescue\n  c\nelse\n  d\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  a\n  d\nrescue NotFound\n  b\nrescue\n  c\nend\n"])
    end

    # Dropping an empty else changes nothing.
    it "skips an empty else clause" do
      expect(mutated_sources("def m\n  a\nrescue\n  b\nelse\nend\n")).to be_empty
    end

    it "skips a rescue around an empty body" do
      expect(mutated_sources("def m\n  begin\n  rescue\n    b\n  else\n    c\n  end\nend\n")).to be_empty
    end

    it "skips a rescue without an else clause" do
      expect(mutated_sources("def m\n  a\nrescue\n  b\nend\n")).to be_empty
    end

    it "produces parseable mutations" do
      source = "def m\n  begin; a; rescue; b; else; c; end\n  d\nrescue StandardError\n  e\nelse\n  f\nensure\n  g\nend\n"
      muts = mutations_for(source)

      expect(muts.length).to eq(2)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["rescue_else_concatenation"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["else"])

      expect(mutated_sources("def m\n  a\nrescue\n  b\nelse\n  c\nend\n", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
