# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RescueHandlerPromotion do
  def mutations_for(source, filter: nil)
    tmpfile = Tempfile.new(["rescue_handler_promotion", ".rb"])
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
    it "replaces a begin block's body and rescue with the handler" do
      source = "def m(id)\n  begin\n    fetch(id)\n  rescue NotFound\n    default\n  end\nend\n"

      expect(mutated_sources(source)).to eq(["def m(id)\n  begin\n    default\n  end\nend\n"])
    end

    it "replaces a method body with its method-level handler" do
      source = "def m(id)\n  fetch(id)\nrescue NotFound\n  log\n  default\nend\n"

      expect(mutated_sources(source)).to eq(["def m(id)\n  log\n  default\nend\n"])
    end

    it "promotes the handler of a block's rescue" do
      source = "def m(ids)\n  ids.map do |id|\n    fetch(id)\n  rescue NotFound\n    default\n  end\nend\n"

      expect(mutated_sources(source)).to eq(["def m(ids)\n  ids.map do |id|\n    default\n  end\nend\n"])
    end

    it "promotes each handler of several rescue clauses separately" do
      source = "def m\n  a\nrescue X\n  b\nrescue Y\n  c\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  b\nend\n", "def m\n  c\nend\n"])
    end

    # The else clause only runs when nothing was rescued, so it goes with the
    # body; ensure runs either way and stays.
    it "drops the else clause and keeps the ensure clause" do
      source = "def m\n  a\nrescue X\n  b\nelse\n  c\nensure\n  d\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  b\nensure\n  d\nend\n"])
    end

    it "drops an empty else clause" do
      source = "def m\n  a\nrescue X\n  b\nelse\nensure\n  d\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  b\nensure\n  d\nend\n"])
    end

    it "promotes an empty handler as nil" do
      source = "def m\n  begin\n    a\n  rescue X\n  end\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  begin\n    nil\n  end\nend\n"])
    end

    it "promotes the fallback of a rescue modifier" do
      expect(mutated_sources("def m(id)\n  fetch(id) rescue default\nend\n")).to eq(["def m(id)\n  default\nend\n"])
      expect(mutated_sources("def m(id)\n  x = fetch(id) rescue default\n  x\nend\n")).to eq(
        ["def m(id)\n  x = default\n  x\nend\n"]
      )
    end

    # Outside the rescue the exception is gone: `e` is no longer bound and
    # `$!` is nil, so the promoted handler fails for that reason alone.
    it "skips a handler that reads the rescued exception" do
      expect(mutated_sources("def m\n  a\nrescue X => e\n  log(e)\nend\n")).to be_empty
      expect(mutated_sources("def m\n  a\nrescue X\n  log($!)\nend\n")).to be_empty
      expect(mutated_sources("def m\n  a rescue $!.message\nend\n")).to be_empty
    end

    it "still promotes a handler that binds the exception without reading it" do
      expect(mutated_sources("def m\n  a\nrescue X => _e\n  b\nend\n")).to eq(["def m\n  b\nend\n"])
      expect(mutated_sources("def m\n  a\nrescue X => e\n  b\nend\n")).to eq(["def m\n  b\nend\n"])
    end

    it "still promotes a handler that reads other globals" do
      expect(mutated_sources("def m\n  a\nrescue X\n  $stdout.puts\nend\n")).to eq(["def m\n  $stdout.puts\nend\n"])
    end

    # Binding the exception to an instance variable or similar leaves it set
    # for code after the rescue; whether that code relies on it cannot be told
    # from the handler, so the handler stays.
    it "skips a handler that binds the exception to anything but a local" do
      expect(mutated_sources("def m\n  a\nrescue X => @error\n  b\nend\n")).to be_empty
    end

    # A bare raise re-raises the rescued error and retry only parses inside a
    # rescue; promoted, both just fail.
    it "skips a handler that re-raises or retries" do
      expect(mutated_sources("def m\n  a\nrescue X\n  log\n  raise\nend\n")).to be_empty
      expect(mutated_sources("def m\n  a\nrescue X\n  fail\nend\n")).to be_empty
      expect(mutated_sources("def m\n  a\nrescue X\n  retry\nend\n")).to be_empty
    end

    it "still promotes a handler that calls fail or raise on a receiver" do
      expect(mutated_sources("def m\n  a\nrescue X\n  ctx.fail\nend\n")).to eq(["def m\n  ctx.fail\nend\n"])
    end

    it "still promotes a handler that raises a new error" do
      expect(mutated_sources("def m\n  a\nrescue X\n  raise Y, \"bad\"\nend\n")).to eq(["def m\n  raise Y, \"bad\"\nend\n"])
    end

    it "promotes only the handlers that qualify" do
      source = "def m\n  a\nrescue X => e\n  log(e)\nrescue Y\n  c\nend\n"

      expect(mutated_sources(source)).to eq(["def m\n  c\nend\n"])
    end

    it "emits nothing for a rescue around an empty body" do
      expect(mutated_sources("def m\n  begin\n  rescue X\n    b\n  end\nend\n")).to be_empty
    end

    it "emits nothing for a begin block without a rescue" do
      expect(mutated_sources("def m\n  begin\n    a\n  ensure\n    b\n  end\nend\n")).to be_empty
    end

    it "produces parseable mutations" do
      source = "def m\n  begin\n    a\n  rescue X\n  end\n  b rescue c\n  d\nrescue Y\n  e\nensure\n  f\nend\n"
      muts = mutations_for(source)

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["rescue_handler_promotion"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["rescue_modifier"])

      expect(mutated_sources("def m\n  a rescue b\nend\n", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
