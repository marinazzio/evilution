# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::AttrAccessorSwap do
  def mutations_for(source, method_name = "first")
    Tempfile.create(["attr_accessor_swap", ".rb"]) do |file|
      File.write(file.path, source)
      subject = Evilution::AST::Parser.new.call(file.path).find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
      described_class.new.call(subject)
    end
  end

  # A class holding the given body lines, then two methods.
  def klass(*lines)
    "class Sample\n#{lines.map { |line| "  #{line}\n" }.join}  def first = 1\n  def second = 2\nend\n"
  end

  # The body lines of each mutant: what stands between `class` and the methods.
  def mutated_lines(source, method_name = "first")
    mutations_for(source, method_name).map do |m|
      m.mutated_source.lines.map(&:chomp).reject { |line| line.strip.empty? || line.match?(/\A(class|module|end|\s+def |\s+end)/) }
       .map(&:strip)
    end
  end

  describe "#call" do
    it "widens a reader to an accessor and removes it, through the first method of the class" do
      expect(mutated_lines(klass("attr_reader :name"))).to eq([["attr_accessor :name"], []])
    end

    it "widens a writer to an accessor and removes it" do
      expect(mutated_lines(klass("attr_writer :name"))).to eq([["attr_accessor :name"], []])
    end

    it "only removes an accessor" do
      expect(mutated_lines(klass("attr_accessor :name"))).to eq([[]])
    end

    it "does not repeat the mutations for later methods" do
      expect(mutations_for(klass("attr_reader :name"), "second")).to be_empty
    end

    it "keeps the names, in every way of writing them" do
      expect(mutated_lines(klass("attr_reader :a, :b")).first).to eq(["attr_accessor :a, :b"])
      expect(mutated_lines(klass("attr_reader(:a, \"b\")")).first).to eq(["attr_accessor(:a, \"b\")"])
      expect(mutated_lines(klass("attr_writer *NAMES")).first).to eq(["attr_accessor *NAMES"])
    end

    it "mutates each declaration in turn" do
      expect(mutated_lines(klass("attr_reader :a", "attr_accessor :b"))).to eq(
        [["attr_accessor :a", "attr_accessor :b"], ["attr_accessor :b"], ["attr_reader :a"]]
      )
    end

    it "reaches a module and a singleton class through their own first method" do
      expect(mutated_lines("module Sample\n  attr_reader :a\n  def first = 1\nend\n")).to eq([["attr_accessor :a"], []])

      source = "class Sample\n  class << self\n    attr_reader :a\n    def first = 1\n  end\nend\n"
      expect(mutations_for(source).map { |m| m.mutated_source.lines[2].strip }).to eq(["attr_accessor :a", ""])
    end

    it "reports the mutations on the line of the declaration" do
      expect(mutations_for(klass("X = 1", "attr_reader :a")).map(&:line)).to eq([3, 3])
    end

    # Removing the declaration there would leave a bare `private` behind.
    it "leaves a declaration wrapped in a visibility call alone" do
      expect(mutations_for(klass("private attr_reader :a"))).to be_empty
    end

    it "leaves a declaration without names, with a receiver or guarded by a modifier alone" do
      expect(mutations_for(klass("attr_reader", "Other.attr_reader :a", "attr_reader :b if legacy?"))).to be_empty
    end

    it "leaves the old attr and other class-level calls alone" do
      expect(mutations_for(klass("attr :a", "attribute :b", "delegate :c, to: :d"))).to be_empty
    end

    it "leaves a call inside a method alone" do
      expect(mutations_for("class Sample\n  def first\n    attr_reader :a\n  end\nend\n")).to be_empty
    end

    it "produces valid Ruby" do
      mutations = mutations_for(klass("attr_reader :a, :b", "attr_writer(*NAMES)", "attr_accessor :c"))

      expect(mutations.length).to eq(5)
      expect(mutations.map(&:parse_status)).to all(eq(:ok))
    end

    it "sets correct operator_name" do
      expect(mutations_for(klass("attr_accessor :a")).map(&:operator_name)).to eq(["attr_accessor_swap"])
    end
  end
end
