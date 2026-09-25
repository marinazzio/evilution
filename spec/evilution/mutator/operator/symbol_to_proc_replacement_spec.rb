# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::SymbolToProcReplacement do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/symbol_to_proc_replacement.rb", __dir__)
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
    tmpfile = Tempfile.new(["symbol_to_proc_replacement", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "swaps a selector from the send-mutation table" do
      expect(mutated_lines(mutations_for("stringify"))).to eq(["items.map(&:to_i)"])
    end

    it "swaps a selector from the collection-replacement table" do
      expect(mutated_lines(mutations_for("firsts"))).to eq(["pairs.map(&:last)"])
    end

    it "emits every replacement listed for the selector" do
      expect(mutated_lines(mutations_for("multiple")))
        .to contain_exactly("words.map(&:lstrip)", "words.map(&:rstrip)")
    end

    it "merges both tables for a selector listed in each" do
      expect(mutated_lines(mutations_for("nested_map")))
        .to contain_exactly("lists.each(&:flat_map)", "lists.each(&:each)")
    end

    it "emits a replacement once when both tables list it" do
      muts = mutations_from_source("def flatten_all(lists)\n  lists.map(&:flat_map)\nend\n")

      expect(mutated_lines(muts)).to eq(["lists.map(&:map)"])
    end

    it "descends into a block-pass expression that holds another block-pass" do
      muts = mutations_from_source("def each_str(lists)\n  lists.each(&->(xs) { xs.map(&:to_s) })\nend\n")

      expect(mutated_lines(muts)).to eq(["lists.each(&->(xs) { xs.map(&:to_i) })"])
    end

    it "swaps a quoted symbol inside its quotes" do
      expect(mutated_lines(mutations_for("quoted"))).to eq(['items.map(&:"downcase")'])
    end

    it "skips replacements that are aliases of the original selector" do
      expect(mutations_for("alias_only")).to be_empty
    end

    it "keeps non-alias replacements for a selector that also has an alias" do
      muts = mutations_from_source("def pick(items)\n  items.select(&:collect)\nend\n")

      expect(mutated_lines(muts)).to eq(["items.select(&:each)"])
    end

    it "skips a selector with no table entry" do
      expect(mutations_for("unknown_selector")).to be_empty
    end

    it "skips a block-pass that is not a symbol" do
      expect(mutations_for("block_variable")).to be_empty
    end

    it "leaves a literal block to the call-site operators" do
      expect(mutations_for("literal_block")).to be_empty
    end

    it "reports the mutation on the line of the block-pass" do
      expect(mutations_for("stringify").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("stringify").map(&:operator_name).uniq).to eq(["symbol_to_proc_replacement"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["block_argument"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#stringify") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
