# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RescueHandlerConcatenation do
  def mutations_for(source, filter: nil)
    tmpfile = Tempfile.new(["rescue_handler_concatenation", ".rb"])
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
    it "runs the handler after the body as well, keeping the rescue" do
      source = "def m(id)\n  begin\n    fetch(id)\n  rescue NotFound\n    rollback\n  end\nend\n"

      expect(mutated_sources(source)).to eq(
        ["def m(id)\n  begin\n    fetch(id)\n    rollback\n  rescue NotFound\n    rollback\n  end\nend\n"]
      )
    end

    it "runs a method-level handler after the method body" do
      source = "def m(id)\n  fetch(id)\nrescue NotFound\n  rollback\nend\n"

      expect(mutated_sources(source)).to eq(["def m(id)\n  fetch(id)\n  rollback\nrescue NotFound\n  rollback\nend\n"])
    end

    it "runs a block's handler after the block body" do
      source = "def m(ids)\n  ids.each do |id|\n    fetch(id)\n  rescue NotFound\n    skip\n  end\nend\n"

      expect(mutated_sources(source)).to eq(
        ["def m(ids)\n  ids.each do |id|\n    fetch(id)\n    skip\n  rescue NotFound\n    skip\n  end\nend\n"]
      )
    end

    it "copies every statement of a longer handler" do
      source = "def m\n  a\nrescue X\n  log\n  rollback\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  a\n  log\n  rollback\nrescue X\n  log\n  rollback\nend\n"])
    end

    it "appends after the last statement of a longer body" do
      source = "def m\n  a\n  b\nrescue X\n  c\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  a\n  b\n  c\nrescue X\n  c\nend\n"])
    end

    it "uses each handler of several rescue clauses in turn" do
      source = "def m\n  a\nrescue X\n  b\nrescue Y\n  c\nend\n"

      expect(mutated_sources(source)).to eq(
        ["def m\n  a\n  b\nrescue X\n  b\nrescue Y\n  c\nend\n", "def m\n  a\n  c\nrescue X\n  b\nrescue Y\n  c\nend\n"]
      )
    end

    it "leaves else and ensure clauses in place" do
      source = "def m\n  a\nrescue X\n  b\nelse\n  c\nensure\n  d\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  a\n  b\nrescue X\n  b\nelse\n  c\nensure\n  d\nend\n"])
    end

    it "joins with a semicolon on a single line" do
      source = "def m\n  begin; a; rescue X; b; end\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  begin; a; b; rescue X; b; end\nend\n"])
    end

    # Running nothing after the body changes nothing.
    it "skips an empty handler" do
      expect(mutated_sources("def m\n  a\nrescue X\nend\n")).to be_empty
    end

    # A handler that only produces a value changes nothing but the return
    # value when run after the body; RescueHandlerPromotion probes that value.
    it "skips a handler that only produces a value" do
      %w[nil false true 0 :none "" [] {} self LIMIT @fallback fallback return].each do |handler|
        source = "def m(fallback)\n  a\nrescue X\n  #{handler}\nend\n"

        expect(mutated_sources(source)).to be_empty, "expected no mutant for a `#{handler}` handler"
      end
      expect(mutated_sources("def m(ids)\n  ids.each do\n    a\n  rescue X\n    next\n  end\nend\n")).to be_empty
    end

    it "still runs a handler with a non-empty literal or a value after a statement" do
      expect(mutated_sources("def m\n  a\nrescue X\n  [build]\nend\n").length).to eq(1)
      expect(mutated_sources("def m\n  a\nrescue X\n  log\n  nil\nend\n").length).to eq(1)
      expect(mutated_sources("def m\n  a\nrescue X\n  return b\nend\n").length).to eq(1)
    end

    it "still uses a later handler after skipping an earlier one" do
      expect(mutated_sources("def m\n  a\nrescue X\n  nil\nrescue Y\n  log\nend\n")).to eq(
        ["def m\n  a\n  log\nrescue X\n  nil\nrescue Y\n  log\nend\n"]
      )
      expect(mutated_sources("def m\n  a\nrescue X => e\n  log(e)\nrescue Y\n  log\nend\n").length).to eq(1)
    end

    it "skips a rescue around an empty body" do
      expect(mutated_sources("def m\n  begin\n  rescue X\n    b\n  end\nend\n")).to be_empty
    end

    # In the body the exception does not exist and a bare raise or retry has
    # nothing to act on, so these handlers would fail for that reason alone.
    it "skips handlers that only work inside the rescue" do
      expect(mutated_sources("def m\n  a\nrescue X => e\n  log(e)\nend\n")).to be_empty
      expect(mutated_sources("def m\n  a\nrescue X\n  log($!)\nend\n")).to be_empty
      expect(mutated_sources("def m\n  a\nrescue X\n  raise\nend\n")).to be_empty
      expect(mutated_sources("def m\n  a\nrescue X\n  retry\nend\n")).to be_empty
    end

    # A modifier rescue sits in value position, where a statement sequence
    # does not fit.
    it "leaves a rescue modifier alone" do
      expect(mutated_sources("def m\n  a rescue b\nend\n")).to be_empty
    end

    it "produces parseable mutations" do
      source = "def m\n  begin; a; rescue X; b; end\n  c\nrescue Y\n  d\n  e\nend\n"
      muts = mutations_for(source)

      expect(muts.length).to eq(2)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["rescue_handler_concatenation"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["rescue"])

      expect(mutated_sources("def m\n  a\nrescue X\n  b\nend\n", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
