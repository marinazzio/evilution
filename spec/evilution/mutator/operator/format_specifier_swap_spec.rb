# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::FormatSpecifierSwap do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["format_specifier_swap", ".rb"])
    tmpfile.write("class Fmt\n  def call(a, b)\n#{body}  end\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  # The line each mutation rewrote.
  def mutated_lines(muts)
    muts.map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "drops the flags and width of a specifier" do
      muts = mutations_for("    format(\"%05d\", a)\n")

      expect(mutated_lines(muts)).to eq(["format(\"%d\", a)"])
    end

    it "drops the precision of a float and renders it as a string" do
      muts = mutations_for("    sprintf(\"%.2f\", a)\n")

      expect(mutated_lines(muts)).to eq(["sprintf(\"%f\", a)", "sprintf(\"%s\", a)"])
    end

    it "renders numeric conversions other than integers as strings" do
      %w[f e g x o b].each do |type|
        expect(mutated_lines(mutations_for("    format(\"%#{type}\", a)\n"))).to eq(["format(\"%s\", a)"])
      end
    end

    # For an integer argument %d and %s print the same digits.
    it "keeps an integer conversion as it is" do
      expect(mutations_for("    format(\"%d %i %u\", a, a, a)\n")).to be_empty
    end

    it "drops flags alone and width alone" do
      expect(mutated_lines(mutations_for("    format(\"%+d\", a)\n"))).to eq(["format(\"%d\", a)"])
      expect(mutated_lines(mutations_for("    format(\"%5d\", a)\n"))).to eq(["format(\"%d\", a)"])
      expect(mutated_lines(mutations_for("    format(\"%.3s\", a)\n"))).to eq(["format(\"%s\", a)"])
    end

    it "drops the width of a string conversion" do
      muts = mutations_for("    format(\"%-10s|\", a)\n")

      expect(mutated_lines(muts)).to eq(["format(\"%s|\", a)"])
    end

    it "keeps the name of a named specifier" do
      muts = mutations_for("    format(\"%<count>08.3f\", count: a)\n")

      expect(mutated_lines(muts)).to eq(["format(\"%<count>f\", count: a)", "format(\"%<count>s\", count: a)"])
    end

    it "mutates each specifier of a string separately" do
      muts = mutations_for("    format(\"%05d of %.1f\", a, b)\n")

      expect(mutated_lines(muts)).to eq(
        ["format(\"%d of %.1f\", a, b)", "format(\"%05d of %f\", a, b)", "format(\"%05d of %s\", a, b)"]
      )
    end

    it "mutates the format string of String#% and printf" do
      expect(mutated_lines(mutations_for("    \"%05d\" % a\n"))).to eq(["\"%d\" % a"])
      expect(mutated_lines(mutations_for("    printf(\"%05d\", a)\n"))).to eq(["printf(\"%d\", a)"])
    end

    it "mutates the explicit method form of String#%" do
      expect(mutated_lines(mutations_for("    \"%05d\".%(a)\n"))).to eq(["\"%d\".%(a)"])
    end

    it "mutates a format call nested in the arguments of another" do
      muts = mutations_for("    format(\"%05d\", format(\"%.2f\", a))\n")

      expect(mutated_lines(muts)).to eq(
        [
          "format(\"%d\", format(\"%.2f\", a))",
          "format(\"%05d\", format(\"%f\", a))",
          "format(\"%05d\", format(\"%s\", a))"
        ]
      )
    end

    it "mutates a single-quoted format string" do
      muts = mutations_for("    format('%05d', a)\n")

      expect(mutated_lines(muts)).to eq(["format('%d', a)"])
    end

    it "leaves an escaped percent sign and template references alone" do
      expect(mutations_for("    format(\"100%% of %s\", a)\n")).to be_empty
      expect(mutations_for("    format(\"%{name} items\", name: a)\n")).to be_empty # rubocop:disable Style/FormatStringToken
    end

    # A `*` width or precision consumes an argument of its own; dropping it
    # shifts every argument after it.
    it "leaves a specifier with a star width or precision alone" do
      expect(mutations_for("    format(\"%*d\", a, b)\n")).to be_empty
      expect(mutations_for("    format(\"%.*f\", a, b)\n")).to be_empty
    end

    it "leaves character and inspect conversions alone" do
      expect(mutations_for("    format(\"%c %p\", a, b)\n")).to be_empty
    end

    it "leaves format strings that are not plain literals alone" do
      expect(mutations_for("    format(\"\#{a} %05d\", b)\n")).to be_empty
      expect(mutations_for("    format(a, b)\n")).to be_empty
      expect(mutations_for("    format\n")).to be_empty
      expect(mutations_for("    format(<<~FMT, a)\n      %05d\n    FMT\n")).to be_empty
    end

    it "leaves other calls with a string argument alone" do
      expect(mutations_for("    log(\"%05d\", a)\n")).to be_empty
      expect(mutations_for("    a.format(\"%05d\", b)\n")).to be_empty
      expect(mutations_for("    \"%05d\" + a\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    format(\"%<count>08.3f\", count: a)\n    \"%x\" % b\n")

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    format(\"%05d\", a)\n")

      expect(muts.map(&:operator_name)).to eq(["format_specifier_swap"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=format}"])

      muts = mutations_for("    format(\"%05d\", a)\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
