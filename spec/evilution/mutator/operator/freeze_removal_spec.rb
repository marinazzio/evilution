# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::FreezeRemoval do
  def mutations_for(source, method_name = "first")
    Tempfile.create(["freeze_removal", ".rb"]) do |file|
      File.write(file.path, source)
      subject = Evilution::AST::Parser.new.call(file.path).find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
      described_class.new.call(subject)
    end
  end

  # A class holding the given body lines, then two methods.
  def klass(*lines, magic: false)
    header = magic ? "# frozen_string_literal: true\n\n" : ""
    "#{header}class Sample\n#{lines.map { |line| "  #{line}\n" }.join}  def first = 1\n  def second = 2\nend\n"
  end

  # The body lines of each mutant.
  def mutated_lines(source, method_name = "first")
    mutations_for(source, method_name).map do |m|
      m.mutated_source.lines.map(&:chomp).reject { |line| line.empty? || line.match?(/\A(#|class|end|  def )/) }.map(&:strip)
    end
  end

  describe "#call" do
    it "drops the freeze of a constant through the first method of the class" do
      expect(mutated_lines(klass("LIST = %w[a b].freeze"))).to eq([["LIST = %w[a b]"]])
    end

    it "does not repeat the mutation for later methods" do
      expect(mutations_for(klass("LIST = %w[a b].freeze"), "second")).to be_empty
    end

    it "drops the freeze of each constant in turn" do
      expect(mutated_lines(klass("A = [1].freeze", "B = { a: 1 }.freeze")))
        .to eq([["A = [1]", "B = { a: 1 }.freeze"], ["A = [1].freeze", "B = { a: 1 }"]])
    end

    it "drops an outer and a nested freeze separately" do
      expect(mutated_lines(klass("MAP = { a: [1].freeze }.freeze")))
        .to eq([["MAP = { a: [1].freeze }"], ["MAP = { a: [1] }.freeze"]])
    end

    it "keeps the rest of a chain" do
      expect(mutated_lines(klass("NAMES = LIST.map(&:to_s).freeze"))).to eq([["NAMES = LIST.map(&:to_s)"]])
      expect(mutated_lines(klass("SIZE = [1].freeze.size"))).to eq([["SIZE = [1].size"]])
    end

    it "keeps the parentheses of a grouped receiver" do
      expect(mutated_lines(klass("ALL = (A + B).freeze"))).to eq([["ALL = (A + B)"]])
    end

    it "drops a freeze written with safe navigation" do
      expect(mutated_lines(klass("LIST = build&.freeze"))).to eq([["LIST = build"]])
    end

    it "reaches a namespaced constant and a conditional assignment" do
      expect(mutated_lines(klass("Sample::LIST = [1].freeze"))).to eq([["Sample::LIST = [1]"]])
      expect(mutated_lines(klass("LIST ||= [1].freeze"))).to eq([["LIST ||= [1]"]])
    end

    it "reaches a constant in a module and in a nested class through its own first method" do
      source = "module Outer\n  A = [1].freeze\n  class Inner\n    B = [2].freeze\n    def first = 1\n  end\n  def self.second = 2\nend\n"

      expect(mutations_for(source, "first").map { |m| m.mutated_source.lines[3].strip }).to eq(["B = [2]"])
      expect(mutations_for(source, "second").map { |m| m.mutated_source.lines[1].strip }).to eq(["A = [1]"])
    end

    it "reports the mutation on the line of the freeze" do
      expect(mutations_for(klass("A = 1", "LIST = [1].freeze")).map(&:line)).to eq([3])
    end

    # These values are frozen whether or not freeze is called.
    it "skips a literal that is frozen anyway" do
      lines = ["A = :a.freeze", "B = 1.freeze", "C = 1.5.freeze", "D = nil.freeze", "E = true.freeze", "F = (1..2).freeze",
               "G = /a/.freeze", "H = 1..2"]

      expect(mutations_for(klass(*lines))).to be_empty
    end

    it "skips a string literal under the frozen_string_literal comment" do
      expect(mutations_for(klass('NAME = "a".freeze', magic: true))).to be_empty
    end

    it "drops the freeze of a string literal without that comment" do
      expect(mutated_lines(klass('NAME = "a".freeze'))).to eq([['NAME = "a"']])
    end

    it "drops the freeze of an interpolated string, which the comment does not freeze" do
      expect(mutated_lines(klass("NAME = \"a\#{B}\".freeze", magic: true))).to eq([["NAME = \"a\#{B}\""]])
    end

    it "takes the comment only from the top of the file" do
      source = "class Sample\n  # frozen_string_literal: true\n  NAME = \"a\".freeze\n  def first = 1\nend\n"

      expect(mutations_for(source).map { |m| m.mutated_source.lines[2].strip }).to eq(['NAME = "a"'])
    end

    it "goes by the last expression of a group" do
      expect(mutations_for(klass("A = (B; 1..2).freeze", "C = ((:a)).freeze"))).to be_empty
      expect(mutated_lines(klass("A = (1; [B]).freeze"))).to eq([["A = (1; [B])"]])
    end

    it "leaves a freeze with arguments or without a receiver alone" do
      expect(mutations_for(klass("A = freeze", "B = LIST.freeze(1)"))).to be_empty
    end

    it "leaves code that is not a constant definition alone" do
      expect(mutations_for(klass("@list = [1].freeze", "register [1].freeze", "LIST = [1]"))).to be_empty
    end

    it "leaves a freeze inside a method to the call operators" do
      source = "class Sample\n  def first\n    [1].freeze\n  end\nend\n"

      expect(mutations_for(source)).to be_empty
    end

    it "produces valid Ruby" do
      mutations = mutations_for(klass("MAP = { a: [1].freeze }.freeze", "ALL = (A + B).freeze", "NAMES = LIST.map(&:to_s).freeze"))

      expect(mutations).not_to be_empty
      expect(mutations.map(&:parse_status)).to all(eq(:ok))
    end

    it "sets correct operator_name" do
      expect(mutations_for(klass("LIST = [1].freeze")).map(&:operator_name)).to eq(["freeze_removal"])
    end
  end
end
