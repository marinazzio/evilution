# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::DigToFetchChain do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/dig_to_fetch_chain.rb", __dir__)
  end
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

  def mutations_from_source(inline_source)
    Tempfile.create(["dig_to_fetch_chain", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "fetches the first key and digs the rest" do
      expect(mutated_lines(mutations_for("two_keys"))).to eq(["config.fetch(:db).dig(:host)"])
    end

    it "keeps every remaining key in the dig" do
      expect(mutated_lines(mutations_for("three_keys"))).to eq(["config.fetch(:db).dig(:primary, :host)"])
    end

    it "handles a call without parentheses" do
      expect(mutated_lines(mutations_for("without_parens"))).to eq(["config.fetch(:db).dig :host"])
    end

    it "keeps safe navigation" do
      expect(mutated_lines(mutations_for("safe_navigation"))).to eq(["config&.fetch(:db).dig(:host)"])
    end

    it "keeps a compound first key intact" do
      muts = mutations_from_source("def t(c, env)\n  c.dig(env.to_sym, :host)\nend\n")

      expect(mutated_lines(muts)).to eq(["c.fetch(env.to_sym).dig(:host)"])
    end

    it "keeps multi-line remaining keys as written" do
      muts = mutations_from_source("def t(c)\n  c.dig(\n    :db,\n    :host\n  )\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def t(c)\n  c.fetch(:db).dig(\n    :host\n  )\nend\n"])
    end

    it "rewrites a dig nested in another dig's key" do
      muts = mutations_from_source("def t(a, b)\n  a.dig(b.dig(:x, :y), :z)\nend\n")

      expect(mutated_lines(muts)).to contain_exactly(
        "a.fetch(b.dig(:x, :y)).dig(:z)", "a.dig(b.fetch(:x).dig(:y), :z)"
      )
    end

    it "skips a single key" do
      expect(mutations_for("single_key")).to be_empty
    end

    it "skips a splat" do
      expect(mutations_for("splat")).to be_empty
    end

    it "skips a splat among the remaining keys" do
      expect(mutations_from_source("def t(c, rest)\n  c.dig(:db, *rest)\nend\n")).to be_empty
    end

    it "skips a receiverless call" do
      expect(mutations_for("receiverless")).to be_empty
    end

    it "skips other methods" do
      expect(mutations_for("other_method")).to be_empty
    end

    it "skips a call with a block" do
      expect(mutations_from_source("def t(c)\n  c.dig(:a, :b) { 1 }\nend\n")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("two_keys").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("two_keys").map(&:operator_name).uniq).to eq(["dig_to_fetch_chain"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=dig}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#two_keys") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
