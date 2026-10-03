# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::OffByOneBoundary do
  def mutations_for(body, signature: "n, m, items", filter: nil)
    tmpfile = Tempfile.new(["off_by_one_boundary", ".rb"])
    tmpfile.write("class Bounds\n  def call(#{signature})\n#{body}  end\nend\n")
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
    it "runs a times loop one fewer time" do
      muts = mutations_for("    n.times { tick }\n")

      expect(mutated_lines(muts)).to eq(["(n - 1).times { tick }"])
    end

    it "groups a compound count before subtracting" do
      expect(mutated_lines(mutations_for("    (n + m).times { tick }\n"))).to eq(["((n + m) - 1).times { tick }"])
      expect(mutated_lines(mutations_for("    items.size.times { tick }\n"))).to eq(["(items.size - 1).times { tick }"])
    end

    it "lowers the bound of upto and downto" do
      expect(mutated_lines(mutations_for("    1.upto(n) { |i| tick(i) }\n"))).to eq(["1.upto(n - 1) { |i| tick(i) }"])
      expect(mutated_lines(mutations_for("    n.downto(m) { |i| tick(i) }\n"))).to eq(["n.downto(m - 1) { |i| tick(i) }"])
    end

    it "lowers the count of collection slicing methods" do
      %w[take first last drop each_slice each_cons].each do |selector|
        expect(mutated_lines(mutations_for("    items.#{selector}(n)\n"))).to eq(["items.#{selector}(n - 1)"])
      end
    end

    it "groups a count argument that is not a primary expression" do
      expect(mutated_lines(mutations_for("    items.first(n > m ? n : m)\n"))).to eq(
        ["items.first((n > m ? n : m) - 1)"]
      )
      expect(mutated_lines(mutations_for("    items.take(n + m)\n"))).to eq(["items.take((n + m) - 1)"])
    end

    it "keeps a call written without parentheses valid" do
      muts = mutations_for("    items.first n\n")

      expect(mutated_lines(muts)).to eq(["items.first n - 1"])
    end

    # A literal count is shifted by IntegerLiteral already.
    it "leaves literal counts alone" do
      expect(mutations_for("    3.times { tick }\n")).to be_empty
      expect(mutations_for("    1.upto(10) { |i| tick(i) }\n")).to be_empty
      expect(mutations_for("    items.first(2)\n")).to be_empty
    end

    it "leaves calls without a single count argument alone" do
      expect(mutations_for("    items.first\n")).to be_empty
      expect(mutations_for("    items.first(n, m)\n")).to be_empty
      expect(mutations_for("    n.times(m)\n")).to be_empty
    end

    # A splat, keywords or forwarded arguments stand in the argument list
    # without being a count; subtracting from them would not parse.
    it "leaves an argument that is not a plain value alone" do
      expect(mutations_for("    items.take(*n)\n")).to be_empty
      expect(mutations_for("    items.first(**n)\n")).to be_empty
      expect(mutations_for("    items.first(count: n)\n")).to be_empty
      expect(mutations_for("    items.take(...)\n", signature: "items, ...")).to be_empty
    end

    # With safe navigation a nil count yields nil; `nil - 1` would raise
    # instead, which tests the nil, not the boundary.
    it "leaves a safe-navigation call alone" do
      expect(mutations_for("    n&.times { tick }\n")).to be_empty
      expect(mutations_for("    items&.first(n)\n")).to be_empty
    end

    it "leaves other methods alone" do
      expect(mutations_for("    items.fetch(n)\n")).to be_empty
      expect(mutations_for("    n.succ\n")).to be_empty
    end

    it "shifts nested counts independently" do
      muts = mutations_for("    items.first(n).take(m)\n")

      expect(mutated_lines(muts)).to eq(["items.first(n).take(m - 1)", "items.first(n - 1).take(m)"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("    (n + m).times { tick }\n    items.first n\n    items.take(n > m ? n : m)\n")

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    n.times { tick }\n")

      expect(muts.map(&:operator_name)).to eq(["off_by_one_boundary"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=times}"])

      muts = mutations_for("    n.times { tick }\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
