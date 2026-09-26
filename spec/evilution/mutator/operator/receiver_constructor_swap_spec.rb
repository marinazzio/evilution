# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ReceiverConstructorSwap do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/receiver_constructor_swap.rb", __dir__)
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
    Tempfile.create(["receiver_constructor_swap", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def selectors(muts)
    muts.map { |m| m.mutated_slice[/\.(\w+)\(/, 1] }
  end

  let(:date_siblings) { %w[jd civil strptime iso8601 rfc3339 xmlschema rfc2822 rfc822 httpdate jisx0301] }

  describe "#call" do
    it "swaps Date.parse for each sibling constructor" do
      expect(selectors(mutations_for("date"))).to match_array(date_siblings)
    end

    it "swaps DateTime.parse for the same siblings" do
      expect(selectors(mutations_for("date_time"))).to match_array(date_siblings)
    end

    it "swaps Time.parse for the siblings Time defines, without strptime" do
      expect(selectors(mutations_for("time"))).to match_array(%w[iso8601 xmlschema rfc2822 rfc822 httpdate])
    end

    it "keeps the receiver and arguments" do
      lines = mutations_for("date").map { |m| m.mutated_slice.strip }

      expect(lines).to include("Date.iso8601(value)", "Date.strptime(value)")
    end

    it "matches a top-level constant receiver" do
      expect(selectors(mutations_for("top_level"))).to match_array(date_siblings)
    end

    it "matches a call without parentheses" do
      muts = mutations_from_source("def t(v)\n  Time.parse v\nend\n")

      expect(muts.map { |m| m.mutated_slice.strip }).to include("Time.iso8601 v")
    end

    it "swaps a parse nested in another call" do
      muts = mutations_from_source("def t(v)\n  wrap(Time.parse(v))\nend\n")

      expect(muts.map { |m| m.mutated_slice.strip }).to include("wrap(Time.iso8601(v))")
    end

    it "skips another receiver" do
      expect(mutations_for("other_receiver")).to be_empty
    end

    it "skips a variable receiver" do
      expect(mutations_for("variable_receiver")).to be_empty
    end

    it "skips a namespaced constant with the same name" do
      expect(mutations_from_source("def t(v)\n  Acme::Date.parse(v)\nend\n")).to be_empty
    end

    it "skips a selector with no siblings" do
      expect(mutations_for("other_selector")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("time").map(&:line).uniq).to eq([11])
    end

    it "names the operator" do
      expect(mutations_for("date").map(&:operator_name).uniq).to eq(["receiver_constructor_swap"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=parse}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#time") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(5)
    end
  end
end
