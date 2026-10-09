# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::MemoizationBreak do
  def mutations_of(body)
    Tempfile.create(["memoization_break", ".rb"]) do |file|
      File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
      described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
    end
  end

  # The body of the method after each mutation.
  def mutated_bodies(body)
    mutations_of(body).map { |m| m.mutated_source.lines[2..-3].join }
  end

  describe "#call" do
    it "turns a memoizing assignment into a plain one" do
      expect(mutated_bodies("    @total ||= compute(x)\n")).to eq(["    @total = compute(x)\n"])
    end

    it "keeps the rest of the statement" do
      expect(mutated_bodies("    return @total ||= compute(x) if x\n")).to eq(["    return @total = compute(x) if x\n"])
    end

    it "keeps a multi-line value" do
      body = "    @total ||= begin\n      compute(x)\n    end\n"

      expect(mutated_bodies(body)).to eq(["    @total = begin\n      compute(x)\n    end\n"])
    end

    it "mutates each memoizing assignment, nested ones too" do
      body = "    @a ||= x\n    @b ||= (@c ||= x)\n"

      expect(mutated_bodies(body)).to eq(
        ["    @a = x\n    @b ||= (@c ||= x)\n", "    @a ||= x\n    @b = (@c ||= x)\n", "    @a ||= x\n    @b ||= (@c = x)\n"]
      )
    end

    it "reports the mutation on the line of the assignment" do
      expect(mutations_of("    x\n    @total ||= x\n").map(&:line)).to eq([4])
    end

    # `value ||= default` fills in a missing value; it does not memoize.
    it "leaves a local variable alone" do
      expect(mutations_of("    y = nil\n    y ||= x\n")).to be_empty
    end

    it "leaves other targets alone" do
      expect(mutations_of("    @@total ||= x\n    $total ||= x\n    @cache[x] ||= x\n    self.total ||= x\n")).to be_empty
    end

    it "leaves other assignments to an instance variable alone" do
      expect(mutations_of("    @total = x\n    @total &&= x\n    @total += x\n")).to be_empty
    end

    it "produces valid Ruby" do
      bodies = ["    @total ||= compute(x)\n", "    @total ||= begin\n      compute(x)\n    end\n", "    record(@a ||= x)\n"]
      mutations = bodies.flat_map { |body| mutations_of(body) }

      expect(mutations).not_to be_empty
      expect(mutations.map(&:parse_status)).to all(eq(:ok))
    end

    it "sets correct operator_name" do
      expect(mutations_of("    @total ||= x\n").map(&:operator_name)).to eq(["memoization_break"])
    end
  end
end
