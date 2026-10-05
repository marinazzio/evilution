# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ReturnKeywordRemoval do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["return_keyword_removal", ".rb"])
    tmpfile.write("def m(x, xs)\n#{body}end\n")
    tmpfile.flush
    described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_lines(body, filter: nil)
    mutations_for(body, filter: filter).map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "lets a guard clause fall through instead of returning" do
      expect(mutated_lines("  return :neg if x.negative?\n  compute(x)\n")).to eq([":neg if x.negative?"])
    end

    it "drops the keyword of an early return inside a conditional" do
      expect(mutated_lines("  if x\n    return 1\n  end\n  2\n")).to eq(["1"])
    end

    it "drops the keyword of a return inside a block" do
      expect(mutated_lines("  xs.each { |y| return y if y }\n  nil\n")).to eq(["xs.each { |y| y if y }"])
    end

    it "wraps several returned values in an array" do
      expect(mutated_lines("  return x, 1 if x\n  nil\n")).to eq(["[x, 1] if x"])
      expect(mutated_lines("  return *xs if x\n  nil\n")).to eq(["[*xs] if x"])
    end

    # In tail position the value falls out of the method anyway, so dropping
    # the keyword changes nothing.
    it "skips a return in tail position" do
      expect(mutated_lines("  compute(x)\n  return x\n")).to be_empty
      expect(mutated_lines("  return x if x\n")).to be_empty
      expect(mutated_lines("  if x\n    return 1\n  else\n    return 2\n  end\n")).to be_empty
      expect(mutated_lines("  case x\n  when 1 then return :a\n  else return :b\n  end\n")).to be_empty
      expect(mutated_lines("  begin\n    return x\n  rescue StandardError\n    return nil\n  end\n")).to be_empty
      expect(mutated_lines("  (return x)\n")).to be_empty
    end

    it "still mutates a return in a branch that is not in tail position" do
      expect(mutated_lines("  if x\n    return 1\n  else\n    return 2\n  end\n  3\n")).to eq(%w[1 2])
    end

    # A return in a block leaves the method; without the keyword the value
    # would only be the block's.
    it "treats a return at the end of a block as an early exit" do
      expect(mutated_lines("  xs.each do |y|\n    return y\n  end\n")).to eq(["y"])
    end

    it "skips a return in tail position of a lambda and mutates an earlier one" do
      expect(mutated_lines("  -> { return x }\n")).to be_empty
      expect(mutated_lines("  -> { return 1 if x\n  2 }\n")).to eq(["-> { 1 if x"])
    end

    it "skips a bare return" do
      expect(mutated_lines("  return if x\n  compute(x)\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("  return x, 1 if x\n  xs.each { |y| return y }\n  return *xs if x\n  nil\n")

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["return_keyword_removal"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["return"])

      expect(mutated_lines("  return 1 if x\n  2\n", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
